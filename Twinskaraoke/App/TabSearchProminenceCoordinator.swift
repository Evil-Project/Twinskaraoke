import SwiftUI
import UIKit

/// Only maintains Search prominence. SwiftUI exclusively owns minimization and
/// accessory placement; this bridge must never change tabBarMinimizeBehavior.
final class TabSearchProminenceCoordinator {
    private(set) weak var controller: UITabBarController?
    private var attachmentTask: Task<Void, Never>?
    private var generation = 0
    private weak var attachedWindow: UIWindow?

    isolated deinit { attachmentTask?.cancel() }

    func attach(to window: UIWindow) {
        // Layout and SwiftUI updates can request attachment repeatedly in one
        // frame. Coalesce them, and never mutate UIKit presentation mid-layout.
        guard attachedWindow !== window || attachmentTask == nil else { return }
        attachedWindow = window
        generation += 1
        attachmentTask?.cancel()
        let token = generation
        // Tabs can be installed after their controller. No transition timers.
        attachmentTask = Task { @MainActor [weak self, weak window] in
            guard let self, let window, generation == token, !Task.isCancelled else { return }
            resolve(in: window)
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, generation == token else { return }
                resolve(in: window)
            }
            attachmentTask = nil
        }
    }

    func detach() {
        generation += 1
        attachmentTask?.cancel()
        attachmentTask = nil
        controller = nil
        attachedWindow = nil
    }

    private func resolve(in window: UIWindow) {
        controller = Self.find(in: window.rootViewController)
        if let controller { Self.keepSearchProminent(in: controller) }
    }

    private static func find(in root: UIViewController?) -> UITabBarController? {
        guard let root else { return nil }
        if let tab = root as? UITabBarController { return tab }
        for child in root.children {
            if let tab = find(in: child) { return tab }
        }
        return find(in: root.presentedViewController)
    }

    private static func keepSearchProminent(in controller: UITabBarController) {
        guard #available(iOS 27.0, *),
              let search = controller.tabs.first(where: { $0 is UISearchTab }) as? UISearchTab else { return }
        if !search.automaticallyActivatesSearch {
            search.automaticallyActivatesSearch = true
        }
        #if compiler(>=6.4)
        let current = controller.prominentTabIdentifier
        guard current != search.identifier else { return }
        controller.prominentTabIdentifier = search.identifier
        #else
        let setter = NSSelectorFromString("setProminentTabIdentifier:")
        let getter = NSSelectorFromString("prominentTabIdentifier")
        guard controller.responds(to: setter), controller.responds(to: getter) else { return }
        let current = controller.perform(getter)?.takeUnretainedValue() as? String
        guard current != search.identifier else { return }
        controller.perform(setter, with: search.identifier as NSString)
        #endif
        DebugLogger.log("Search prominence controller=\(ObjectIdentifier(controller)), tabs=\(controller.tabs.map { String(describing: type(of: $0)) + ":" + $0.identifier }), automatic=\(search.automaticallyActivatesSearch), previous=\(current ?? "nil"), assigned=\(search.identifier)", category: .ui)
    }

}

struct TabSearchProminenceInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> TabSearchInstallerView { TabSearchInstallerView() }
    func updateUIView(_ view: TabSearchInstallerView, context: Context) {
        if let window = view.window { view.coordinator.attach(to: window) }
        else { view.coordinator.detach() }
    }
    static func dismantleUIView(_ view: TabSearchInstallerView, coordinator: ()) {
        view.coordinator.detach()
    }
}

final class TabSearchInstallerView: UIView {
    let coordinator = TabSearchProminenceCoordinator()
    override func layoutSubviews() {
        super.layoutSubviews()
        if let window { coordinator.attach(to: window) }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { coordinator.attach(to: window) }
        else { coordinator.detach() }
    }
}
