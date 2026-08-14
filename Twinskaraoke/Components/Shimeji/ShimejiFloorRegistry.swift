import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Tracks the mini player's top edge so `ShimejiEngine` can treat it as a
    /// floor Shimeji can land on.
    ///
    /// `MiniPlayerBar` pushes its own frame here as SwiftUI lays it out. This
    /// used to be a poll: the bar was a `UIView` owned by LNPopupUI, with no
    /// SwiftUI geometry to read and no change notification offered, so
    /// `ShimejiOverlayController` re-measured it twice a second and Shimeji
    /// visibly lagged the bar whenever the tab bar minimized. A view we own
    /// reports the change instead of being asked about it.
    ///
    /// A plain (non-actor) singleton for the same reason as the old floor
    /// registry this replaces: the only reader is `ShimejiOverlayController`,
    /// already `@MainActor`, and the only writer is a SwiftUI geometry
    /// callback, which also runs on the main thread.
    final class ShimejiMiniPlayerTracker {
        static let shared = ShimejiMiniPlayerTracker()

        private init() {}

        /// The bar's current top edge in window coordinates — the same space
        /// `ShimejiEngine.bounds` is tracked in. Nil while no bar is showing,
        /// which is what puts Shimeji back on the tab bar's edge.
        private(set) var topEdgeY: CGFloat?

        /// - Parameter frame: the bar's frame in global coordinates, or nil
        ///   when the bar leaves the screen.
        func report(frame: CGRect?) {
            guard let frame, frame.height > 0 else {
                update(topEdgeY: nil)
                return
            }
            update(topEdgeY: frame.minY)
        }

        private func update(topEdgeY newValue: CGFloat?) {
            guard newValue != topEdgeY else { return }
            topEdgeY = newValue
            ShimejiEngine.shared.miniPlayerY = newValue
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
