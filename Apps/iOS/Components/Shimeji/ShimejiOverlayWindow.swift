import SwiftUI

#if canImport(UIKit)
    import UIKit
    final class ShimejiOverlayWindow: UIWindow {
        private let touchMargin: CGFloat = 8
        var engine: ShimejiEngine?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let size = ShimejiEngine.displaySize
            let overSprite = engine?.instances.contains { instance in
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
            guard overSprite == true else { return nil }
            return super.hitTest(point, with: event)
        }
    }
    @MainActor
    final class ShimejiOverlayController {
        let engine = ShimejiEngine()

        private var window: ShimejiOverlayWindow?
        private var boundsTrackingTimer: Timer?
        private weak var trackedScene: UIWindowScene?

        init() {}

        func show(in scene: UIWindowScene) {
            if trackedScene === scene, window != nil { return }
            hide()
            let window = ShimejiOverlayWindow(windowScene: scene)
            window.engine = engine
            window.backgroundColor = .clear
            window.isUserInteractionEnabled = true
            window.windowLevel = .normal + 1
            let host = UIHostingController(rootView: ShimejiOverlayRootView(engine: engine))
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = false
            self.window = window

            startTrackingBounds(in: scene)
        }

        func hide() {
            engine.stop()
            boundsTrackingTimer?.invalidate()
            boundsTrackingTimer = nil
            trackedScene = nil
            window?.isHidden = true
            window = nil
        }

        /// Keeps `engine.bounds` in sync with the screen —
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
            engine.bounds = scene.effectiveGeometry.coordinateSpace.bounds
            engine.navBarY = ShimejiNavBarLocator.topEdgeY(in: scene, excluding: window)
        }
    }

    private struct ShimejiOverlayRootView: View {
        let engine: ShimejiEngine

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    ForEach(engine.instances) { instance in
                        ShimejiSpriteView(instance: instance, engine: engine)
                    }
                }
                .onAppear {
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
