import Foundation

nonisolated struct BandleGlobalStats: Decodable, Sendable {
    let date: String?
    let songId: String?
    let songTitle: String?
    let totalPlayers: Int?
    let totalWinners: Int?
    let winRate: Double?
    let averageAttempt: Double?
    let perfectScores: Int?
    let attemptDistribution: [String: Int]?

    init(
        date: String? = nil,
        songId: String? = nil,
        songTitle: String? = nil,
        totalPlayers: Int? = nil,
        totalWinners: Int? = nil,
        winRate: Double? = nil,
        averageAttempt: Double? = nil,
        perfectScores: Int? = nil,
        attemptDistribution: [String: Int]? = nil
    ) {
        self.date = date
        self.songId = songId
        self.songTitle = songTitle
        self.totalPlayers = totalPlayers
        self.totalWinners = totalWinners
        self.winRate = winRate
        self.averageAttempt = averageAttempt
        self.perfectScores = perfectScores
        self.attemptDistribution = attemptDistribution
    }
}
