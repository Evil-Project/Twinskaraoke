import Foundation

nonisolated struct BandleLeaderboardEntry: Decodable, Identifiable, Sendable {
    var userId: String?
    var username: String?
    var userAvatarUrl: String?
    var rank: Int?
    var score: Int?
    var badge: String?
    var frameTheme: Int?
    var date: String?
    var attemptNumber: Int?
    var timeSpent: String?
    var completedAt: String?
    var isPerfect: Bool?
    var gamesPlayed: Int?
    var gamesWon: Int?
    var totalScore: Int64?
    var averageAttempt: Double?
    var perfectScores: Int?
    var weeklyStreak: Int?
    var monthlyStreak: Int?
    var daysActive: Int?
    var winRate: Double?
    var totalGamesPlayed: Int?
    var totalGamesWon: Int?
    var currentStreak: Int?
    var longestStreak: Int?
    var memberSince: String?

    var id: String { userId ?? username ?? String(rank ?? 0) }
    var played: Int? { totalGamesPlayed ?? gamesPlayed }
    var won: Int? { totalGamesWon ?? gamesWon }
    var streak: Int? { weeklyStreak ?? monthlyStreak ?? currentStreak }
    var avatarURL: URL? { URL(string: userAvatarUrl ?? "") }

    init(
        userId: String? = nil,
        username: String? = nil,
        userAvatarUrl: String? = nil,
        rank: Int? = nil,
        score: Int? = nil,
        badge: String? = nil,
        frameTheme: Int? = nil,
        date: String? = nil,
        attemptNumber: Int? = nil,
        timeSpent: String? = nil,
        completedAt: String? = nil,
        isPerfect: Bool? = nil,
        gamesPlayed: Int? = nil,
        gamesWon: Int? = nil,
        totalScore: Int64? = nil,
        averageAttempt: Double? = nil,
        perfectScores: Int? = nil,
        weeklyStreak: Int? = nil,
        monthlyStreak: Int? = nil,
        daysActive: Int? = nil,
        winRate: Double? = nil,
        totalGamesPlayed: Int? = nil,
        totalGamesWon: Int? = nil,
        currentStreak: Int? = nil,
        longestStreak: Int? = nil,
        memberSince: String? = nil
    ) {
        self.userId = userId
        self.username = username
        self.userAvatarUrl = userAvatarUrl
        self.rank = rank
        self.score = score
        self.badge = badge
        self.frameTheme = frameTheme
        self.date = date
        self.attemptNumber = attemptNumber
        self.timeSpent = timeSpent
        self.completedAt = completedAt
        self.isPerfect = isPerfect
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.totalScore = totalScore
        self.averageAttempt = averageAttempt
        self.perfectScores = perfectScores
        self.weeklyStreak = weeklyStreak
        self.monthlyStreak = monthlyStreak
        self.daysActive = daysActive
        self.winRate = winRate
        self.totalGamesPlayed = totalGamesPlayed
        self.totalGamesWon = totalGamesWon
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.memberSince = memberSince
    }
}
