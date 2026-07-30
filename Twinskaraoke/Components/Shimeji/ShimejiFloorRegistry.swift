import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Tracks the live on-screen frame of the mini player (LNPopupUI's
    /// popup bar) so `ShimejiEngine` can treat its top edge as a floor
    /// Shimeji can land on. LNPopupUI owns and lays out this view itself —
    /// there's no SwiftUI geometry to read — so the only way to know where
    /// it actually is on screen is to hold the live `UIView` handed back by
    /// `.popupBarCustomizer` in `ContentView` and ask it directly.
    ///
    /// A plain (non-actor) singleton for the same reason as the old floor
    /// registry this replaces: the only reader is `ShimejiOverlayController`,
    /// already `@MainActor`, and the only writer is the customizer callback,
    /// which SwiftUI also runs on the main thread.
    final class ShimejiMiniPlayerTracker {
        static let shared = ShimejiMiniPlayerTracker()

        private weak var barView: UIView?

        private init() {}

        /// Called from `.popupBarCustomizer` whenever LNPopupUI (re)builds
        /// the bar, so this always points at the current one.
        func register(_ barView: UIView) {
            self.barView = barView
        }

        /// The bar's current top edge, in its own window's coordinate space
        /// — the same space `ShimejiEngine.bounds` is tracked in, since both
        /// ultimately come from the same key window. Nil if the bar hasn't
        /// been registered yet or isn't actually attached to a window (not
        /// laid out yet, or the popup bar isn't showing).
        var topEdgeY: CGFloat? {
            guard let barView, let window = barView.window, barView.bounds.height > 0 else { return nil }
            let frameInWindow = barView.convert(barView.bounds, to: window)
            guard frameInWindow.height > 0 else { return nil }
            return frameInWindow.minY
        }
    }

    /// Finds the app's live `UITabBar` (SwiftUI's `TabView` is backed by a
    /// real `UITabBarController`/`UITabBar` under the hood) so the engine
    /// can rest idle instances on its actual top edge instead of the literal
    /// screen bottom, which sits visually beneath and behind it. Unlike the
    /// mini player there's no customizer hook to register through, so this
    /// walks the window hierarchy instead — cheap enough for the same 0.5s
    /// poll that already re-measures bounds and the mini player.
    enum ShimejiNavBarLocator {
        /// - Parameter excluding: the Shimeji overlay window itself, so the
        ///   search doesn't waste time descending into a view tree that by
        ///   construction never contains a tab bar.
        static func topEdgeY(in scene: UIWindowScene, excluding excludedWindow: UIWindow?) -> CGFloat? {
            for window in scene.windows where window !== excludedWindow {
                guard let tabBar = firstTabBar(in: window), !tabBar.isHidden, tabBar.bounds.height > 0 else { continue }
                let frameInWindow = tabBar.convert(tabBar.bounds, to: window)
                guard frameInWindow.height > 0 else { continue }
                return frameInWindow.minY
            }
            return nil
        }

        private static func firstTabBar(in view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar { return tabBar }
            for subview in view.subviews {
                if let found = firstTabBar(in: subview) { return found }
            }
            return nil
        }
    }
#endif
