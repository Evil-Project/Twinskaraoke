#if canImport(UIKit)
    import MediaPlayer
    import SwiftUI

    enum SystemVolumeReconciliation {
        static func value(
            currentVolume: Double,
            systemVolume: Float,
            isUserScrubbing: Bool
        ) -> Double {
            isUserScrubbing ? currentVolume : Double(systemVolume)
        }
    }

    struct SystemVolumeBridge: UIViewRepresentable {
        @Binding var volume: Double
        @Binding var isUserScrubbing: Bool

        /// Holds the throttle clock across the struct's many re-creations —
        /// SwiftUI rebuilds the representable on every update, so this cannot
        /// live in the struct itself.
        final class Coordinator {
            var lastPushTime: TimeInterval = 0
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        /// 20Hz is indistinguishable to a hand moving a volume slider, so pushing
        /// any faster is pure waste.
        private static let pushInterval: TimeInterval = 1.0 / 20.0

        func makeUIView(context _: Context) -> MPVolumeView {
            let view = MPVolumeView(frame: .zero)
            view.alpha = 0.0001
            synchronizeVolume(from: view)
            return view
        }

        func updateUIView(_ uiView: MPVolumeView, context: Context) {
            guard isUserScrubbing else { return }
            // SwiftUI calls this at display rate (up to 120Hz) while a drag is
            // live, and every `sendActions` below crosses into the system volume
            // server.  The value guard alone does not help: during a drag
            // the target moves every frame, so it passes every time.
            let now = ProcessInfo.processInfo.systemUptime
            guard now - context.coordinator.lastPushTime >= Self.pushInterval else { return }
            context.coordinator.lastPushTime = now

            DispatchQueue.main.async {
                guard let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first else { return }
                let target = Float(max(0, min(1, volume)))
                if abs(slider.value - target) > 0.005 {
                    slider.setValue(target, animated: false)
                    slider.sendActions(for: .valueChanged)
                }
            }
        }

        private func synchronizeVolume(from view: MPVolumeView) {
            DispatchQueue.main.async {
                view.layoutIfNeeded()
                guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
                let reconciledVolume = SystemVolumeReconciliation.value(
                    currentVolume: volume,
                    systemVolume: slider.value,
                    isUserScrubbing: isUserScrubbing
                )
                if volume != reconciledVolume {
                    volume = reconciledVolume
                }
            }
        }
    }
#endif
