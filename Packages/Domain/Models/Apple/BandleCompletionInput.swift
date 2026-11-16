import Foundation

nonisolated struct BandleCompletionInput: Sendable {
    let won: Bool
    let attemptNumber: Int
    let songId: String?
    let songTitle: String?
    let artist: String?
    let attempts: [BandleAttempt]
    /// Nil when the choice made at `/start` isn't known here (a game resumed
    /// on another device); the field is then left out of the request.
    let excludeFromLeaderboard: Bool?
    let mode: BandleMode

    init(
        won: Bool,
        attemptNumber: Int,
        songId: String? = nil,
        songTitle: String? = nil,
        artist: String? = nil,
        attempts: [BandleAttempt],
        excludeFromLeaderboard: Bool? = false,
        mode: BandleMode = .normal
    ) {
        self.won = won
        self.attemptNumber = attemptNumber
        self.songId = songId
        self.songTitle = songTitle
        self.artist = artist
        self.attempts = attempts
        self.excludeFromLeaderboard = excludeFromLeaderboard
        self.mode = mode
    }
}
