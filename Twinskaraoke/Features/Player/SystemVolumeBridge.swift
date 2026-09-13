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

    /// Native system volume with documented track and thumb customization.
    struct SystemVolumeBridge: UIViewRepresentable {
        @Environment(\.colorScheme) private var colorScheme

        final class Coordinator {
            var colorScheme: ColorScheme?
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> MPVolumeView {
            let view = MPVolumeView(frame: .zero)
            style(view, coordinator: context.coordinator)
            return view
        }

        func updateUIView(_ view: MPVolumeView, context: Context) {
            style(view, coordinator: context.coordinator)
        }

        private func style(_ view: MPVolumeView, coordinator: Coordinator) {
            guard coordinator.colorScheme != colorScheme else { return }
            coordinator.colorScheme = colorScheme
            let foreground = colorScheme == .dark ? UIColor.white : UIColor.black
            // Preserve the system's touch target, but draw no visible knob.
            let thumb = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in }
            for state: UIControl.State in [.normal, .highlighted, .disabled] {
                let height: CGFloat = state == .highlighted ? 12 : 7
                let opacity: CGFloat = state == .disabled ? 0.4 : 1
                view.setVolumeThumbImage(thumb, for: state)
                view.setMinimumVolumeSliderImage(
                    trackImage(color: foreground.withAlphaComponent(opacity), height: height), for: state
                )
                view.setMaximumVolumeSliderImage(
                    trackImage(color: foreground.withAlphaComponent(0.18 * opacity), height: height), for: state
                )
            }
        }

        private func trackImage(color: UIColor, height: CGFloat) -> UIImage {
            let size = CGSize(width: height * 2 + 1, height: height)
            return UIGraphicsImageRenderer(size: size).image { _ in
                color.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2).fill()
            }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: height, bottom: 0, right: height))
        }
    }
#endif
