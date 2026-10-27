#if canImport(UIKit)
    import AVFAudio
    import MediaPlayer
    import SwiftUI
    import UIKit.UIGestureRecognizerSubclass

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
        @Environment(\.appReduceMotion) private var reduceMotion

        final class Coordinator {
            var colorScheme: ColorScheme?
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> SystemVolumeContainer {
            let view = SystemVolumeContainer()
            view.reduceMotion = reduceMotion
            style(view.volumeView, coordinator: context.coordinator)
            return view
        }

        func updateUIView(_ view: SystemVolumeContainer, context: Context) {
            view.reduceMotion = reduceMotion
            style(view.volumeView, coordinator: context.coordinator)
            view.setNeedsLayout()
        }

        private func style(_ view: MPVolumeView, coordinator: Coordinator) {
            guard coordinator.colorScheme != colorScheme else { return }
            coordinator.colorScheme = colorScheme
            let foreground = colorScheme == .dark ? UIColor.white : UIColor.black
            // Preserve the system's touch target, but draw no visible knob.
            let thumb = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in }
            for state: UIControl.State in [.normal, .highlighted, .disabled] {
                // Keep the native drawing rectangle identical in every state.
                // The container expands the rendered control without clipping the track.
                let height: CGFloat = 7
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

    /// Own the layout around MPVolumeView; Apple does not support subclassing it.
    final class SystemVolumeContainer: UIView {
        let volumeView = MPVolumeView(frame: .zero)
        var reduceMotion = false
        private(set) var isPressed = false
        private var scrubHaptics = ScrubHapticFeedback()
        private var volumeObservation: NSKeyValueObservation?

        init() {
            super.init(frame: .zero)
            clipsToBounds = false
            volumeView.clipsToBounds = false
            addSubview(volumeView)
            let observer = VolumeTouchObserver()
            observer.onPressed = { [weak self] pressed in self?.setPressed(pressed) }
            observer.onCancelled = { [weak self] in
                guard let self else { return }
                _ = self.scrubHaptics.end(cancelled: true)
                self.setPressed(false)
            }
            addGestureRecognizer(observer)
            volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) {
                [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor [weak self] in
                    self?.scrubHaptics.update(Double(value))?.play()
                }
            }
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            volumeView.bounds = CGRect(origin: .zero, size: bounds.size)
            // Its first track geometry depends on its own layout at the final size.
            // Measuring before this pass leaves the initial position stale until a touch.
            volumeView.layoutIfNeeded()
            let track = volumeView.volumeSliderRect(forBounds: volumeView.bounds)
            let scale: CGFloat = isPressed ? 12.0 / 7.0 : 1
            // MPVolumeView places its track above the midpoint of a tall view.
            // Keep the actual track, including its expanded state, on the icon baseline.
            let trackMidY = track.isEmpty ? volumeView.bounds.midY : track.midY
            volumeView.center = CGPoint(
                x: bounds.midX,
                y: bounds.midY + (volumeView.bounds.midY - trackMidY) * scale
            )
            volumeView.transform = CGAffineTransform(scaleX: 1, y: scale)
        }

        func setPressed(_ pressed: Bool) {
            guard isPressed != pressed else { return }
            if pressed {
                AppHaptic.detent.prepare()
                scrubHaptics.begin()?.play()
                // Seed the first notch without a second impact on top of the grab.
                _ = scrubHaptics.update(Double(AVAudioSession.sharedInstance().outputVolume))
            } else {
                scrubHaptics.end()?.play()
            }
            isPressed = pressed
            setNeedsLayout()
            if reduceMotion {
                layoutIfNeeded()
            } else {
                UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.layoutIfNeeded()
                }
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                _ = scrubHaptics.end(cancelled: true)
                setPressed(false)
                return
            }
            volumeView.setNeedsLayout()
            setNeedsLayout()
            // Window attachment can finish installing the native control after this callback.
            // Reconcile once on the next main-queue turn, without waiting for interaction.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.volumeView.setNeedsLayout()
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        }
    }

    /// Observe contact without recognizing a competing gesture or consuming slider touches.
    private final class VolumeTouchObserver: UIGestureRecognizer {
        var onPressed: ((Bool) -> Void)?
        var onCancelled: (() -> Void)?

        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onPressed?(true)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            onPressed?(false)
            state = .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            onCancelled?()
            state = .failed
        }

        override func reset() {
            super.reset()
            onCancelled?()
        }
    }
#endif
