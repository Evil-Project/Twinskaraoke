import Foundation

@MainActor
protocol CompanionPlaybackRouting: AnyObject {
    var watchOwnsAudio: Bool { get }
    func playbackDidChange(periodic: Bool)
    func routeToWatch(_ action: CompanionPlayback.Action, song: Song?, queue: [Song]?,
                      position: Double?, streamURL: URL?, artworkURL: URL?,
                      shuffleEnabled: Bool?, sleepMinutes: Int?, sleepAtEndOfSong: Bool?) -> Bool
}
