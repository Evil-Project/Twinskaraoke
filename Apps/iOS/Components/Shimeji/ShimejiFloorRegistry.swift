import SwiftUI

#if canImport(UIKit)
    import UIKit

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
