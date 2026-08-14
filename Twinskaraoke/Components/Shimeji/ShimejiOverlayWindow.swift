import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// A borderless window stacked above the app's main window so Shimeji can
    /// walk over any screen, including the tab bar and any presented sheets.
    /// Touches only register where a sprite actually is; everywhere else
    /// passes straight through to the app underneath.
    ///
    /// This checks against the engine's own tracked sprite positions rather
    /// than relying on the hit-tested UIView's identity: SwiftUI content
    /// hosted via UIHostingController is typically backed by a single root
    /// UIView (not one UIView per SwiftUI node), so UIKit's normal hitTest
    /// can't distinguish "over a sprite" from "over empty space" on its own.
    final class ShimejiOverlayWindow: UIWindow {
        /// Small margin beyond the sprite's actual drawn footprint so a
        /// drag doesn't require pixel-perfect precision, without ballooning
        /// out far enough to block taps on nearby UI.
        private let touchMargin: CGFloat = 8

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let size = ShimejiEngine.displaySize
            let overSprite = ShimejiEngine.shared.instances.contains { instance in
                // instance.position is the sprite's feet; it's drawn from
                // there upward by `size`, so the hit rect has to match that
                // — not a box symmetric around the feet, which used to eat
                // into the empty space below the sprite (blocking taps on
                // whatever was underneath, like tab bar buttons) while
                // barely covering the actual visible art above it.
                let rect = CGRect(
                    x: instance.position.x - size / 2 - touchMargin,
                    y: instance.position.y - size - touchMargin,
                    width: size + touchMargin * 2,
                    height: size + touchMargin * 2
                )
                return rect.contains(point)
            }
            guard overSprite else { return nil }
            return super.hitTest(point, with: event)
        }
    }

    /// Owns the overlay window's lifecycle. One instance for the app.
    @MainActor
    final class ShimejiOverlayController {
        static let shared = ShimejiOverlayController()

        private var window: ShimejiOverlayWindow?
        private var boundsTrackingTimer: Timer?
        private weak var trackedScene: UIWindowScene?

        private init() {}

        func show(in scene: UIWindowScene) {
            guard window == nil else { return }
            let window = ShimejiOverlayWindow(windowScene: scene)
            window.backgroundColor = .clear
            window.isUserInteractionEnabled = true
            window.windowLevel = .normal + 1
            let host = UIHostingController(rootView: ShimejiOverlayRootView())
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = false
            self.window = window

            startTrackingBounds(in: scene)
        }

        func hide() {
            boundsTrackingTimer?.invalidate()
            boundsTrackingTimer = nil
            trackedScene = nil
            window?.isHidden = true
            window = nil
        }

        /// Keeps `ShimejiEngine.shared.bounds` in sync with the screen —
        /// the actual device screen, since this is a standalone window at
        /// scene level rather than sized to any particular app content view,
        /// which is what lets climbing happen at the real screen edge even
        /// while something like the full-screen player is presented over
        /// the app's own window underneath — so falling/walking/climbing
        /// instances stay clamped correctly through rotation, Split View
        /// resizing, etc. The mini player's own edge is not polled here — it
        /// is a SwiftUI view now, so it reports its frame as it changes.
        private func startTrackingBounds(in scene: UIWindowScene) {
            boundsTrackingTimer?.invalidate()
            trackedScene = scene
            let timer = Timer(
                timeInterval: 0.5,
                target: self,
                selector: #selector(refreshTrackedBounds),
                userInfo: nil,
                repeats: true
            )
            RunLoop.main.add(timer, forMode: .common)
            boundsTrackingTimer = timer
            refreshTrackedBounds()
        }

        @objc private func refreshTrackedBounds() {
            guard let scene = trackedScene else { return }
            ShimejiEngine.shared.bounds = scene.effectiveGeometry.coordinateSpace.bounds
            ShimejiEngine.shared.navBarY = ShimejiNavBarLocator.topEdgeY(in: scene, excluding: window)
        }
    }

    private struct ShimejiOverlayRootView: View {
        private let engine = ShimejiEngine.shared

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    ForEach(engine.instances) { instance in
                        ShimejiSpriteView(instance: instance)
                    }
                }
                .onAppear {
                    // Fallback in case the scene-based bounds tracker hasn't
                    // fired yet on first frame.
                    if engine.bounds == .zero {
                        engine.bounds = proxy.frame(in: .global)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)
        }
    }
#endif
