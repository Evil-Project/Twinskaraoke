import Foundation

nonisolated struct BandleUserData: Decodable, Sendable {
    let lastPlayed: String?
    let streak: Int?
    let gamesPlayed: Int?
    let gamesWon: Int?
    let lastResult: BandleResult?
    let attemptDistribution: [String: Int]?
    let longestStreak: Int?

    init(
        lastPlayed: String? = nil,
        streak: Int? = nil,
        gamesPlayed: Int? = nil,
        gamesWon: Int? = nil,
        lastResult: BandleResult? = nil,
        attemptDistribution: [String: Int]? = nil,
        longestStreak: Int? = nil
    ) {
        self.lastPlayed = lastPlayed
        self.streak = streak
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.lastResult = lastResult
        self.attemptDistribution = attemptDistribution
        self.longestStreak = longestStreak
    }

    var winPercentage: Double {
        guard let gamesPlayed, gamesPlayed > 0 else { return 0 }
        return Double(gamesWon ?? 0) / Double(gamesPlayed) * 100
    }
}
