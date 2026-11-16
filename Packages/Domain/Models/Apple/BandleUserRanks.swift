import Foundation

nonisolated struct BandleUserRanks: Decodable, Sendable {
    let userId: String?
    let username: String?
    let dailyRank: Int?
    let weeklyRank: Int?
    let monthlyRank: Int?
    let globalRank: Int?
    let currentStreak: Int?
    let longestStreak: Int?

    init(
        userId: String? = nil,
        username: String? = nil,
        dailyRank: Int? = nil,
        weeklyRank: Int? = nil,
        monthlyRank: Int? = nil,
        globalRank: Int? = nil,
        currentStreak: Int? = nil,
        longestStreak: Int? = nil
    ) {
        self.userId = userId
        self.username = username
        self.dailyRank = dailyRank
        self.weeklyRank = weeklyRank
        self.monthlyRank = monthlyRank
        self.globalRank = globalRank
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
    }
}
