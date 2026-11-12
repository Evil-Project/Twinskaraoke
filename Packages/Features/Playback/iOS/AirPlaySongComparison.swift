import AVFoundation
import Combine
import Foundation

/// The signed comparison build opts in at compile time so it can launch from the Home Screen.
@MainActor
enum AirPlaySongComparison {
    static var isEnabled: Bool {
        #if DEBUG && AIRPLAY_SONG_COMPARISON
            true
        #else
            false
        #endif
    }

    static var outputs: [AVAudioSession.Port] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
    }

    static func shouldUsePlayer(outputs: [AVAudioSession.Port], url: URL?, processingActive: Bool) -> Bool {
        outputs.contains(.airPlay) && url?.isFileURL == true && !processingActive
    }

    static func makePlayer(url: URL) -> AVQueuePlayer {
        let player = AVQueuePlayer(items: [AVPlayerItem(url: url)])
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = true
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        return player
    }
    static func start(_ player: AVQueuePlayer, at position: TimeInterval) {
        let time = CMTime(seconds: position.isFinite ? max(0, position) : 0, preferredTimescale: 600)
        if time > .zero { player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) }
        player.play()
    }

    static func resume(_ player: AVQueuePlayer) {
        if let duration = player.currentItem?.duration.seconds, duration.isFinite,
           player.currentTime().seconds >= duration {
            player.seek(to: .zero)
        }
        player.play()
    }
}

@MainActor
enum ManagedAVPlayerObservation {
    static func observe(
        player: AVPlayer,
        item: AVPlayerItem,
        onStatus: @escaping (AVPlayerItem.Status) -> Void,
        onState: @escaping () -> Void
    ) -> Set<AnyCancellable> {
        [
            item.publisher(for: \.status, options: [.initial, .new])
                .receive(on: DispatchQueue.main).sink(receiveValue: onStatus),
            item.publisher(for: \.isPlaybackBufferEmpty, options: [.new])
                .receive(on: DispatchQueue.main).sink { _ in onState() },
            item.publisher(for: \.isPlaybackLikelyToKeepUp, options: [.new])
                .receive(on: DispatchQueue.main).sink { _ in onState() },
            player.publisher(for: \.timeControlStatus, options: [.initial, .new])
                .receive(on: DispatchQueue.main).sink { _ in onState() },
        ]
    }

    static func diagnostics(for streamPlayer: AVPlayer?) -> String {
        guard let player = streamPlayer, let item = player.currentItem else { return "stream=none" }
        let duration = item.duration.seconds
        let durationText = duration.isFinite ? String(format: "%.2f", duration) : "unknown"
        let loadedRanges = item.loadedTimeRanges
            .map(\.timeRangeValue)
            .map { range -> String in
                let start = range.start.seconds
                let end = CMTimeAdd(range.start, range.duration).seconds
                guard start.isFinite, end.isFinite else { return "unknown" }
                return String(format: "%.2f-%.2f", start, end)
            }
            .joined(separator: ",")
        let status = switch item.status {
        case .unknown: "unknown"
        case .readyToPlay: "ready"
        case .failed: "failed"
        @unknown default: "unknown-default"
        }
        let itemError = item.error?.localizedDescription ?? "none"
        let playerError = player.error?.localizedDescription ?? "none"
        return "streamDuration=\(durationText), loaded=[\(loadedRanges)], itemStatus=\(status), itemError=\(itemError), playerError=\(playerError)"
    }
}
