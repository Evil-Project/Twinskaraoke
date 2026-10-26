import SwiftUI
import UIKit
struct ZoomPushDismissal: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var suppressor = InteractiveDismissalSuppressor()
    @State private var isDismissing = false
    @State private var isArriving = true
    @State private var arrivalFallbackTask: Task<Void, Never>?
    private static let arrivalFallback = Duration.milliseconds(1500)

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isDismissing)
            .environment(\.zoomPushIsArriving, isArriving)
            .background(
                ZoomDismissalBridge(
                    suppressor: suppressor,
                    onSwipeBack: {
                        isDismissing = true
                        AppHaptic.selection.play()
                        dismiss()
                    },
                    onArrived: { isArriving = false }
                )
            )
            .onAppear {
                isDismissing = false
                suppressor.update()
                arrivalFallbackTask?.cancel()
                arrivalFallbackTask = Task { @MainActor in
                    try? await Task.sleep(for: Self.arrivalFallback)
                    guard !Task.isCancelled else { return }
                    isArriving = false
                }
            }
            .onDisappear {
                suppressor.update()
                arrivalFallbackTask?.cancel()
            }
    }
}

extension View {
    func zoomPushDismissal(isEnabled: Bool) -> some View {
        modifier(ZoomPushDismissalGate(isEnabled: isEnabled))
    }
}

private struct ZoomPushDismissalGate: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(ZoomPushDismissal())
        } else {
            content
        }
    }
}
@MainActor
final class InteractiveDismissalSuppressor {
    /// Single switch for the private-API dependency below.
    ///
    /// Everything here hangs off matching UIKit's dismissal recognisers by type
    /// name. Turning this off restores stock behaviour — the interactive
    /// dismissal comes back, and with it the iOS 26 delay — without touching any
    /// call site. Flip it if a future iOS renames the classes, or if the
    /// dependency is ever considered a submission risk.
    static var isEnabled: Bool {
        // Keep the iOS 26 recognizer workaround scoped to the OS it was
        // measured on. iOS 27 retains the public swipe/touch guard below.
        if #available(iOS 27, *) { return false }
        return true
    }

    weak var navigationController: UINavigationController?
    weak var hostController: UIViewController?
    private var isHolding = false
    func update() {
        guard Self.isEnabled else { return }
        let wants = isTopOfStack
        guard wants != isHolding else { return }
        isHolding = wants
        suppression?.setHolder(ObjectIdentifier(self), wants: wants)
    }

    private var isTopOfStack: Bool {
        guard let navigationController, let hostController else { return false }
        return navigationController.topViewController === hostController
    }

    private var suppression: NavigationDismissalSuppression? {
        navigationController.map { NavigationDismissalSuppression.attached(to: $0) }
    }

    isolated deinit {
        guard isHolding else { return }
        suppression?.setHolder(ObjectIdentifier(self), wants: false)
    }
}
@MainActor
final class NavigationDismissalSuppression {
    private static let driverNames = ["ParallaxTransition", "ContentSwipeDismiss"]

    private static let table = NSMapTable<UINavigationController, NavigationDismissalSuppression>
        .weakToStrongObjects()

    static func attached(to navigationController: UINavigationController) -> NavigationDismissalSuppression {
        if let existing = table.object(forKey: navigationController) { return existing }
        let created = NavigationDismissalSuppression(navigationController: navigationController)
        table.setObject(created, forKey: navigationController)
        return created
    }

    private weak var navigationController: UINavigationController?
    private var holders: Set<ObjectIdentifier> = []
    private var disabled: [UIGestureRecognizer] = []
    private var rescanTask: Task<Void, Never>?
    private var hasMatchedDriver = false

    private init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func setHolder(_ holder: ObjectIdentifier, wants: Bool) {
        let changed = wants ? holders.insert(holder).inserted : holders.remove(holder) != nil
        guard changed else { return }
        apply()
    }

    private func apply() {
        guard !holders.isEmpty else {
            rescanTask?.cancel()
            rescanTask = nil
            for recogniser in disabled {
                recogniser.isEnabled = true
            }
            disabled = []
            assert(hasMatchedDriver, "No interactive-dismissal recogniser matched \(Self.driverNames)")
            hasMatchedDriver = false
            return
        }
        scan()
        rescanTask?.cancel()
        rescanTask = Task { @MainActor [weak self] in
            for step in [50, 200, 500] {
                try? await Task.sleep(for: .milliseconds(step))
                guard !Task.isCancelled, let self, !self.holders.isEmpty else { return }
                self.scan()
            }
        }
    }
    private func scan() {
        guard let root = navigationController?.view else { return }
        var found: [UIGestureRecognizer] = []
        collect(from: root, into: &found)
        guard !found.isEmpty else { return }
        for recogniser in found {
            recogniser.isEnabled = false
        }
        disabled.append(contentsOf: found)
        hasMatchedDriver = true
    }

    private func collect(from view: UIView, into found: inout [UIGestureRecognizer]) {
        for recogniser in view.gestureRecognizers ?? []
        where recogniser.isEnabled && Self.isDismissalDriver(recogniser) {
            found.append(recogniser)
        }
        for subview in view.subviews {
            collect(from: subview, into: &found)
        }
    }

    private static func isDismissalDriver(_ recogniser: UIGestureRecognizer) -> Bool {
        let name = String(describing: type(of: recogniser))
        return driverNames.contains { name.contains($0) }
    }
}
private struct ZoomDismissalBridge: UIViewRepresentable {
    let suppressor: InteractiveDismissalSuppressor
    let onSwipeBack: () -> Void
    let onArrived: () -> Void

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.suppressor = suppressor
        view.swipeBack = context.coordinator
        view.onArrived = onArrived
        context.coordinator.onSwipeBack = onSwipeBack
        return view
    }

    func updateUIView(_ view: BridgeView, context: Context) {
        view.suppressor = suppressor
        view.onArrived = onArrived
        context.coordinator.onSwipeBack = onSwipeBack
    }

    func makeCoordinator() -> SwipeBackDriver { SwipeBackDriver() }

    static func dismantleUIView(_ view: BridgeView, coordinator: SwipeBackDriver) {
        coordinator.uninstall()
    }

    final class BridgeView: UIView {
        var suppressor: InteractiveDismissalSuppressor?
        var swipeBack: SwipeBackDriver?
        var onArrived: (() -> Void)?
        private func reportArrival(host: UIViewController) {
            guard let coordinator = host.transitionCoordinator else {
                onArrived?()
                return
            }
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.onArrived?()
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let suppressor else { return }
            var responder: UIResponder? = self
            var innermostController: UIViewController?
            var hops = 0
            while let current = responder, hops < 60 {
                if let nav = current as? UINavigationController {
                    suppressor.navigationController = nav
                    let host = innermostController.flatMap { controller in
                        sequence(first: controller, next: \.parent).first { $0.parent === nav }
                    }
                    suppressor.hostController = host
                    suppressor.update()
                    guard let host else {
                        onArrived?()
                        return
                    }
                    // Own horizontal content drags, including on iOS 27 where
                    // private recognizer suppression is disabled. This pan
                    // cancels row taps before committing the zoom back.
                    swipeBack?.install(on: host.view)
                    reportArrival(host: host)
                    return
                }
                if innermostController == nil, let controller = current as? UIViewController {
                    innermostController = controller
                }
                responder = current.next
                hops += 1
            }
            onArrived?()
        }
    }
}
@MainActor
final class SwipeBackDriver: NSObject, UIGestureRecognizerDelegate {
    private static let triggerDistance: CGFloat = 60
    private static let flickDistance: CGFloat = 24
    private static let flickVelocity: CGFloat = 800

    var onSwipeBack: () -> Void = {}
    private weak var installedView: UIView?
    private var recogniser: UIPanGestureRecognizer?

    func install(on view: UIView) {
        guard installedView !== view else { return }
        uninstall()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        recogniser = pan
        installedView = view
    }

    func uninstall() {
        if let recogniser, let installedView {
            installedView.removeGestureRecognizer(recogniser)
        }
        recogniser = nil
        installedView = nil
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended, let view = pan.view else { return }
        let sign = Self.backwardSign(in: view)
        let translation = pan.translation(in: view).x * sign
        let velocity = pan.velocity(in: view).x * sign
        guard abs(pan.translation(in: view).y) < translation else { return }
        let isDecided = translation > Self.triggerDistance
            || (translation > Self.flickDistance && velocity > Self.flickVelocity)
        guard isDecided else { return }
        onSwipeBack()
    }
    private static func backwardSign(in view: UIView) -> CGFloat {
        view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view
        else { return false }
        let velocity = pan.velocity(in: view)
        let backward = velocity.x * Self.backwardSign(in: view)
        return backward > 0 && backward > abs(velocity.y) * 1.5
    }
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        guard let scrollView = other.view as? UIScrollView else { return false }
        return other === scrollView.panGestureRecognizer
    }
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf other: UIGestureRecognizer
    ) -> Bool {
        guard let scrollView = other.view as? UIScrollView,
              other === scrollView.panGestureRecognizer
        else { return false }
        return scrollView.contentSize.width > scrollView.bounds.width + 1
    }
}
