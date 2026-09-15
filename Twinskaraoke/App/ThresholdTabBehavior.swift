import SwiftUI
import UIKit

/// On iOS 27, use UIKit's native batch animation as the only policy owner.
/// SwiftUI still owns the tabs and accessory content, but declares no competing
/// minimization modifier on this path. iOS 26 keeps its verified SwiftUI path.
struct ThresholdTabBehavior: ViewModifier {
    let state: TabScrollRevealState?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *), let state {
            content.background(NativeThresholdTabBridge(state: state, revealed: state.isRevealed)
                .frame(width: 0, height: 0))
        } else {
            content.tabBarMinimizeBehavior(state?.isRevealed == true ? .never : .onScrollDown)
        }
    }
}

private struct NativeThresholdTabBridge: UIViewRepresentable {
    let state: TabScrollRevealState
    let revealed: Bool

    func makeUIView(context: Context) -> NativeThresholdTabHost { NativeThresholdTabHost() }
    func updateUIView(_ view: NativeThresholdTabHost, context: Context) {
        view.state = state
        view.revealed = revealed
        view.scheduleUpdate()
    }
    static func dismantleUIView(_ view: NativeThresholdTabHost, coordinator: ()) {
        view.detach()
    }
}

private final class NativeThresholdTabHost: UIView {
    weak var state: TabScrollRevealState?
    var revealed = false
    private let driverID = UUID()
    private weak var controller: UITabBarController?
    private var updateTask: Task<Void, Never>?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { detach() } else { scheduleUpdate() }
    }

    func scheduleUpdate() {
        guard updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            updateTask = nil
            guard let window, let state,
                  let tab = Self.findTab(in: window.rootViewController) else { return }
            controller = tab
            state.installAnimationDriver(owner: driverID) { [weak self] animation, changes, completion in
                guard let self, let controller else {
                    changes()
                    completion()
                    return
                }
                // Commit the native geometry change in the same transaction as
                // the reveal request, rather than waiting for SwiftUI to apply
                // a changed tabBarMinimizeBehavior preference on another pass.
                if animation == nil {
                    UIView.performWithoutAnimation {
                        changes()
                        controller.tabBarMinimizeBehavior = .never
                    }
                    completion()
                } else {
                    CATransaction.begin()
                    CATransaction.setCompletionBlock(completion)
                    withoutActuallyEscaping(changes) { updates in
                        Self.batch(in: controller) {
                            updates()
                            controller.tabBarMinimizeBehavior = .never
                        }
                    }
                    CATransaction.commit()
                }
            }
            let desired: UITabBarController.MinimizeBehavior = revealed ? .never : .onScrollDown
            guard tab.tabBarMinimizeBehavior != desired else { return }
            UIView.performWithoutAnimation { tab.tabBarMinimizeBehavior = desired }
        }
    }

    func detach() {
        updateTask?.cancel()
        updateTask = nil
        state?.removeAnimationDriver(owner: driverID)
        controller = nil
    }

    private static func batch(in controller: UITabBarController, changes: @escaping () -> Void) {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            controller.performBatchUpdates(changes)
            return
        }
        #endif
        // Public iOS 27 API, also usable by binaries built with the iOS 26 SDK.
        let selector = NSSelectorFromString("performBatchUpdates:")
        if controller.responds(to: selector) {
            let block: @convention(block) () -> Void = changes
            controller.perform(selector, with: block)
        } else {
            changes()
        }
    }

    private static func findTab(in root: UIViewController?) -> UITabBarController? {
        guard let root else { return nil }
        if let tab = root as? UITabBarController { return tab }
        for child in root.children {
            if let tab = findTab(in: child) { return tab }
        }
        return nil
    }
}
