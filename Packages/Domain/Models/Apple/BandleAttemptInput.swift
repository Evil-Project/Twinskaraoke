import Foundation

nonisolated struct BandleAttemptInput: Sendable {
    let attemptNumber: Int
    let guessedSongId: String?
    let isSkip: Bool
    let mode: BandleMode

    init(attemptNumber: Int, guessedSongId: String? = nil, isSkip: Bool = false, mode: BandleMode = .normal) {
        self.attemptNumber = attemptNumber
        self.guessedSongId = guessedSongId
        self.isSkip = isSkip
        self.mode = mode
    }
}
