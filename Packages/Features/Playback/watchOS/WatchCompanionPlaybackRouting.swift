import Foundation

@MainActor
protocol WatchCompanionPlaybackRouting: AnyObject {
    var output: CompanionPlayback.Owner { get }
    var canPlayLocally: Bool { get }
    var changingOutput: Bool { get }
    var currentPlaybackSessionID: UUID? { get }
    var currentPlaybackSongID: String? { get }
    func localPlaybackDidChange(periodic: Bool)
    func sendPlaybackCommand(_ command: CompanionPlayback.Command) -> Bool
}
