import Foundation

nonisolated struct BandleAttempt: Codable, Equatable, Identifiable, Sendable {
    let attemptNumber: Int?
    let status: BandleAttemptStatus?
    let guessedSongId: String?
    let guessedSongTitle: String?
    let clipLength: Int
    let attemptedAt: String?

    var id: Int { attemptNumber ?? 0 }

    init(
        clipLength: Int,
        attemptNumber: Int? = nil,
        status: BandleAttemptStatus? = nil,
        guessedSongId: String? = nil,
        guessedSongTitle: String? = nil,
        attemptedAt: String? = nil
    ) {
        self.attemptNumber = attemptNumber
        self.status = status
        self.guessedSongId = guessedSongId
        self.guessedSongTitle = guessedSongTitle
        self.clipLength = clipLength
        self.attemptedAt = attemptedAt
    }
}
