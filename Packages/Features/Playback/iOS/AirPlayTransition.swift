import AVFoundation
import Foundation

nonisolated struct AirPlayTransitionTiming {
    let overlapStart: TimeInterval
    let promotionTime: TimeInterval
    let fade: TimeInterval
    let incomingDuration: TimeInterval

    init?(outgoing: TimeInterval, incoming: TimeInterval, fade: TimeInterval) {
        guard outgoing.isFinite, incoming.isFinite, fade.isFinite, fade > 0,
              outgoing > fade, incoming > fade else { return nil }
        overlapStart = outgoing - fade
        promotionTime = outgoing
        self.fade = fade
        incomingDuration = incoming
    }

    func incomingTime(at time: TimeInterval) -> TimeInterval {
        max(0, time - overlapStart)
    }
}

@MainActor
final class AirPlaySongOperations {
    var retiringSamples: AirPlaySampleSession?
    private var generation = 0
    private(set) var isPending = false

    func begin() -> Int {
        generation &+= 1
        isPending = true
        return generation
    }

    func invalidate() {
        generation &+= 1
        isPending = false
    }
    func isCurrent(_ request: Int) -> Bool { request == generation }

    func waitForOutputDrain(_ request: Int) async -> Bool {
        guard isCurrent(request) else { return false }
        // Build 39 consistently measured about 500 ms of far-end audio after
        // detachment. Leave a small margin in the signed comparison build.
        do { try await Task.sleep(for: .milliseconds(750)) } catch { return false }
        return isCurrent(request)
    }
}

@MainActor
struct AirPlayTransition {
    let item: AVPlayerItem
    let timing: AirPlayTransitionTiming

    static func prepare(outgoing: URL, incoming: URL, fade: TimeInterval, equalPower: Bool) async throws -> Self? {
        let outgoing = AVURLAsset(url: outgoing)
        let incoming = AVURLAsset(url: incoming)
        guard let first = try await outgoing.loadTracks(withMediaType: .audio).first,
              let second = try await incoming.loadTracks(withMediaType: .audio).first else { return nil }
        let firstRange = try await first.load(.timeRange)
        let secondRange = try await second.load(.timeRange)
        guard let timing = AirPlayTransitionTiming(
            outgoing: firstRange.duration.seconds, incoming: secondRange.duration.seconds, fade: fade
        ) else { return nil }

        let composition = AVMutableComposition()
        guard let left = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let right = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let start = CMTime(seconds: timing.overlapStart, preferredTimescale: 48000)
        try left.insertTimeRange(firstRange, of: first, at: .zero)
        try right.insertTimeRange(secondRange, of: second, at: start)

        let mix = AVMutableAudioMix()
        mix.inputParameters = [
            ramp(for: left, timing: timing, incoming: false, equalPower: equalPower),
            ramp(for: right, timing: timing, incoming: true, equalPower: equalPower),
        ]
        let item = AVPlayerItem(asset: composition)
        item.audioMix = mix
        return Self(item: item, timing: timing)
    }

    private static func ramp(
        for track: AVCompositionTrack, timing: AirPlayTransitionTiming, incoming: Bool, equalPower: Bool
    ) -> AVMutableAudioMixInputParameters {
        let input = AVMutableAudioMixInputParameters(track: track)
        let segments = equalPower ? 24 : 1
        func gain(_ fraction: Double) -> Float {
            if equalPower {
                return Float(incoming ? sin(fraction * .pi / 2) : cos(fraction * .pi / 2))
            }
            return Float(incoming ? fraction : 1 - fraction)
        }
        for segment in 0..<segments {
            let from = Double(segment) / Double(segments)
            let to = Double(segment + 1) / Double(segments)
            let start = CMTime(seconds: timing.overlapStart + from * timing.fade, preferredTimescale: 48000)
            let end = CMTime(seconds: timing.overlapStart + to * timing.fade, preferredTimescale: 48000)
            input.setVolumeRamp(fromStartVolume: gain(from), toEndVolume: gain(to), timeRange: CMTimeRange(start: start, end: end))
        }
        return input
    }
}

@MainActor
final class AirPlaySongTimeline {
    let operations = AirPlaySongOperations()
    private var preparation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private(set) var transition: AirPlayTransition?
    private(set) var plan: TransitionCoordinator.TransitionPlan?
    private(set) var offset: TimeInterval = 0
    private(set) var pendingPosition: TimeInterval?

    func prepare(
        from url: URL, plan: TransitionCoordinator.TransitionPlan, ready: @escaping @MainActor (AirPlayTransition) -> Void
    ) {
        preparation?.cancel()
        preparation = Task {
            do {
                guard let result = try await AirPlayTransition.prepare(
                    outgoing: url, incoming: plan.nextFileURL, fade: plan.fadeDuration,
                    equalPower: plan.rampStyle == .equalPower
                ), !Task.isCancelled else { return }
                ready(result)
            } catch {
                DebugLogger.log("AirPlay transition preparation failed: \(error)", category: .playback)
            }
        }
    }

    func install(_ transition: AirPlayTransition, plan: TransitionCoordinator.TransitionPlan) {
        self.transition = transition
        self.plan = plan
        offset = 0
    }

    func promote() -> TransitionCoordinator.TransitionPlan? {
        guard let transition, let plan else { return nil }
        offset = transition.timing.overlapStart
        self.plan = nil
        return plan
    }

    func seek(_ player: AVQueuePlayer, to position: TimeInterval, completion: @escaping @MainActor (Bool) -> Void) {
        let generation = operations.begin()
        pendingPosition = position
        player.currentItem?.cancelPendingSeeks()
        let time = CMTime(seconds: max(0, position) + offset, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.operations.isCurrent(generation) else { return }
                self.operations.invalidate()
                self.pendingPosition = nil
                completion(finished)
            }
        }
    }

    func armStartupTimeout(_ expired: @escaping @MainActor () -> Void) {
        cancelStartupTimeout()
        deadline = Task {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            expired()
        }
    }

    func cancelStartupTimeout() {
        deadline?.cancel()
        deadline = nil
    }

    func cancelPreparation() {
        preparation?.cancel()
        preparation = nil
    }

    func reset() {
        cancelPreparation()
        cancelStartupTimeout()
        operations.invalidate()
        pendingPosition = nil
        transition = nil
        plan = nil
        offset = 0
    }

    func songTime(_ raw: TimeInterval) -> TimeInterval {
        if let pendingPosition { return pendingPosition }
        return raw.isFinite ? max(0, raw - offset) : .nan
    }
}
