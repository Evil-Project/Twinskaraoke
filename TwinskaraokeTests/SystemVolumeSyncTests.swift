import MediaPlayer

import Testing
import UIKit
@testable import Twinskaraoke

@Suite("System volume synchronization")
struct SystemVolumeSyncTests {
    @Test("Volume track stays centered when held and released")
    @MainActor
    func trackAlignmentDuringInteraction() {
        let container = SystemVolumeContainer()
        container.reduceMotion = true
        container.frame = CGRect(x: 0, y: 0, width: 280, height: 44)
        container.layoutIfNeeded()

        for pressed in [false, true, false] {
            container.setPressed(pressed)
            container.layoutIfNeeded()
            let volume = container.volumeView
            let track = volume.volumeSliderRect(forBounds: volume.bounds)
            let midpoint = track.isEmpty ? CGPoint(x: volume.bounds.midX, y: volume.bounds.midY)
                : CGPoint(x: track.midX, y: track.midY)
            let renderedMidpoint = volume.convert(midpoint, to: container)
            #expect(abs(renderedMidpoint.y - container.bounds.midY) < 0.01)
            #expect(abs(volume.transform.d - (pressed ? 12.0 / 7.0 : 1)) < 0.001)
            #expect(!container.clipsToBounds)
            #expect(!volume.clipsToBounds)
        }
        let observer = container.gestureRecognizers?.first
        #expect(observer?.cancelsTouchesInView == false)
        #expect(observer?.delaysTouchesBegan == false)
        #expect(observer?.delaysTouchesEnded == false)
    }

    @Test("First window layout centers volume without a touch")
    @MainActor
    func firstWindowLayoutCentersTrack() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        let container = SystemVolumeContainer()
        controller.view.addSubview(container)
        container.frame = CGRect(x: 32, y: 200, width: 326, height: 44)
        window.isHidden = false
        defer { window.isHidden = true }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        controller.view.layoutIfNeeded()
        let volume = container.volumeView
        volume.layoutIfNeeded()
        let track = volume.volumeSliderRect(forBounds: volume.bounds)
        let midpoint = track.isEmpty ? CGPoint(x: volume.bounds.midX, y: volume.bounds.midY)
            : CGPoint(x: track.midX, y: track.midY)
        #expect(abs(volume.convert(midpoint, to: container).y - container.bounds.midY) < 0.01)
        #expect(!container.isPressed)
    }

    @Test("Removing the volume control clears its pressed appearance")
    @MainActor
    func removalClearsPressedState() {
        let container = SystemVolumeContainer()
        container.reduceMotion = true
        container.setPressed(true)
        container.didMoveToWindow()
        #expect(!container.isPressed)
    }

    @Test("System volume replaces a stale player volume exactly")
    func systemVolumeReplacesStaleVolume() {
        let systemVolume: Float = 0.37

        let volume = SystemVolumeReconciliation.value(
            currentVolume: 0.8,
            systemVolume: systemVolume,
            isUserScrubbing: false
        )

        #expect(volume == Double(systemVolume))
    }

    @Test("System updates do not interrupt active volume scrubbing")
    func systemVolumeWaitsForScrubbingToFinish() {
        let currentVolume = 0.8

        let volume = SystemVolumeReconciliation.value(
            currentVolume: currentVolume,
            systemVolume: 0.2,
            isUserScrubbing: true
        )

        #expect(volume == currentVolume)
    }
}

@Suite("Native scrub haptic feedback")
struct ScrubHapticFeedbackTests {
    @Test("Playback updates are silent outside a gesture")
    func idleUpdatesAreSilent() {
        var feedback = ScrubHapticFeedback()
        #expect(feedback.update(0.3) == nil)
        #expect(feedback.update(1) == nil)
        #expect(feedback.end() == nil)
    }

    @Test("Grab, detents, and release retain the original scrub texture")
    func scrubSequence() {
        var feedback = ScrubHapticFeedback()
        #expect(feedback.begin() == .grab)
        #expect(feedback.begin() == nil)
        #expect(feedback.update(0.3) == nil)
        #expect(feedback.update(0.31) == nil)
        #expect(feedback.update(0.33) == .detent)
        #expect(feedback.end() == .commit)
        #expect(feedback.update(0.5) == nil)
    }

    @Test("Edges latch and rearm after returning to the interior")
    func edgeFeedback() {
        var feedback = ScrubHapticFeedback()
        _ = feedback.begin()
        #expect(feedback.update(0) == .boundary)
        #expect(feedback.update(0) == nil)
        #expect(feedback.update(0.03) == .detent)
        #expect(feedback.update(1) == .boundary)
        #expect(feedback.update(1) == nil)
        #expect(feedback.end(cancelled: true) == nil)
        #expect(feedback.begin() == .grab)
        #expect(feedback.update(0.5) == nil)
    }
}

@Suite("Player pan control ownership")
@MainActor
struct PlayerPanControlTests {
    @Test("Dismissal ignores touches inside native slider controls")
    func sliderOwnsDescendantTouches() {
        let slider = UISlider()
        let child = UIView()
        slider.addSubview(child)
        #expect(!PlayerPanGesture.Coordinator.acceptsTouch(in: slider))
        #expect(!PlayerPanGesture.Coordinator.acceptsTouch(in: child))
    }

    @Test("Player background still accepts dismissal touches")
    func backgroundAcceptsTouches() {
        #expect(PlayerPanGesture.Coordinator.acceptsTouch(in: UIView()))
    }
}
