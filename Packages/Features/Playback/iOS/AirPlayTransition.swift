import AVFoundation
import Foundation

nonisolated struct AirPlayTransitionTiming {
    let outgoingStart: CMTime
    let overlapStart: TimeInterval
    let promotionTime: TimeInterval
    let fade: TimeInterval
    let incomingDuration: TimeInterval

    init?(outgoing: TimeInterval, incoming: TimeInterval, fade: TimeInterval, startingAt: TimeInterval = 0) {
        guard outgoing.isFinite, incoming.isFinite, fade.isFinite, fade > 0,
              outgoing > fade, incoming > fade, startingAt.isFinite, startingAt >= 0 else { return nil }
        outgoingStart = CMTime(seconds: startingAt, preferredTimescale: 48_000)
        promotionTime = outgoingStart.seconds + outgoing
        overlapStart = CMTime(seconds: promotionTime - fade, preferredTimescale: 48_000).seconds
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
    private(set) var generation = 0
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
        // HomePod played about 500 ms of buffered audio after detachment in
        // hardware testing. The extra margin prevented audible overlap.
        do { try await Task.sleep(for: .milliseconds(750)) } catch { return false }
        return isCurrent(request)
    }
}

@MainActor
struct AirPlayTransition {
    let asset: AVComposition
    let tracks: [AVAssetTrack]
    let duration: TimeInterval
    let mix: AVAudioMix
    let timing: AirPlayTransitionTiming

    static func prepare(
        outgoing: URL, incoming: URL, fade: TimeInterval, equalPower: Bool, startingAt: TimeInterval = 0
    ) async throws -> Self? {
        let outgoing = AVURLAsset(url: outgoing)
        let incoming = AVURLAsset(url: incoming)
        guard let first = try await outgoing.loadTracks(withMediaType: .audio).first,
              let second = try await incoming.loadTracks(withMediaType: .audio).first else { return nil }
        let firstRange = try await first.load(.timeRange)
        let secondRange = try await second.load(.timeRange)
        guard let timing = AirPlayTransitionTiming(
            outgoing: firstRange.duration.seconds, incoming: secondRange.duration.seconds, fade: fade, startingAt: startingAt
        ) else { return nil }

        let composition = AVMutableComposition()
        guard let left = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let right = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let start = CMTime(seconds: timing.overlapStart, preferredTimescale: 48000)
        try left.insertTimeRange(firstRange, of: first, at: timing.outgoingStart)
        try right.insertTimeRange(secondRange, of: second, at: start)

        let mix = AVMutableAudioMix()
        mix.inputParameters = [
            ramp(for: left, timing: timing, incoming: false, equalPower: equalPower),
            ramp(for: right, timing: timing, incoming: true, equalPower: equalPower),
        ]
        return Self(
            asset: composition, tracks: [left, right],
            duration: CMTimeAdd(start, secondRange.duration).seconds, mix: mix, timing: timing
        )
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
