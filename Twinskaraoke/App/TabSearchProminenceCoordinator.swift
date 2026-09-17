import SwiftUI
import UIKit

/// Only turns on the Search tab's auto-activation. SwiftUI exclusively owns
/// minimization and accessory placement; this bridge must never change
/// tabBarMinimizeBehavior.
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

    /// Turns on the search tab's own auto-activation. Prominence then follows
    /// from it rather than being assigned: `prominentTabIdentifier` documents
    /// that a nil identifier gives the prominent treatment to a `UISearchTab`
    /// whose `automaticallyActivatesSearch` is on, so writing the identifier
    /// ourselves only restated the default — at the cost of a Swift-version
    /// conditional and a selector dance for an iOS 27-only property.
    ///
    /// `automaticallyActivatesSearch` is iOS 26.0, not 27.0. Gating it behind
    /// `#available(iOS 27.0, *)` — as this did — meant it never ran at all on
    /// the 26.5 deployment target: the field did not take focus when Search was
    /// selected, and cancelling search did not restore the previous tab.
    private static func keepSearchProminent(in controller: UITabBarController) {
        guard let search = controller.tabs.first(where: { $0 is UISearchTab }) as? UISearchTab,
              !search.automaticallyActivatesSearch else { return }
        search.automaticallyActivatesSearch = true
        DebugLogger.log("Search auto-activation controller=\(ObjectIdentifier(controller)), tabs=\(controller.tabs.map { String(describing: type(of: $0)) + ":" + $0.identifier }), assigned=\(search.identifier)", category: .ui)
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
