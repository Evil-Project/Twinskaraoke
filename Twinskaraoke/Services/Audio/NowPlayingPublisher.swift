import Foundation
import MediaPlayer

@MainActor
protocol NowPlayingPublishing: AnyObject {
    var info: [String: Any]? { get set }
}

@MainActor
final class SystemNowPlayingPublisher: NowPlayingPublishing {
    var info: [String: Any]? {
        get { MPNowPlayingInfoCenter.default().nowPlayingInfo }
        set { MPNowPlayingInfoCenter.default().nowPlayingInfo = newValue }
    }
}

@MainActor
enum NowPlayingInfoBuilder {
    static func make(
        song: Song,
        playbackRate: Double,
        isLiveStream: Bool,
        duration: TimeInterval,
        elapsed: TimeInterval,
        existingArtwork: Any?
    ) -> [String: Any] {
        let originalArtists = song.originalArtists?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let artist: String
        if let originalArtists, !originalArtists.isEmpty {
            artist = originalArtists
        } else {
            artist = song.artistName
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyMediaType: MPMediaType.music.rawValue,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: isLiveStream,
        ]
        if let existingArtwork {
            info[MPMediaItemPropertyArtwork] = existingArtwork
        }
        if !isLiveStream {
            info[MPMediaItemPropertyPlaybackDuration] = max(0, duration)
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = min(
                max(0, elapsed),
                max(0, duration)
            )
        }
        return info
    }
}
