import Foundation

nonisolated struct BandleLeaderboard: Decodable, Sendable {
    let date: String?
    let mode: BandleMode?
    let songId: String?
    let songTitle: String?
    let totalPlayers: Int?
    let totalPlaysIncludingGuests: Int?
    let totalWins: Int?
    let totalLosses: Int?
    let winRate: Double?
    let lossRate: Double?
    let entries: [BandleLeaderboardEntry]?
    let lastUpdated: String?
    let averageAttempt: Double?
    let perfectScoreCount: Int?
    let attemptDistribution: [String: Int]?
    let isInvalid: Bool?
    let invalidationMessage: String?
    let weekStartDate: String?
    let weekEndDate: String?
    let weekNumber: Int?
    let year: Int?
    let month: Int?
    let monthName: String?

    init(
        date: String? = nil,
        mode: BandleMode? = nil,
        songId: String? = nil,
        songTitle: String? = nil,
        totalPlayers: Int? = nil,
        totalPlaysIncludingGuests: Int? = nil,
        totalWins: Int? = nil,
        totalLosses: Int? = nil,
        winRate: Double? = nil,
        lossRate: Double? = nil,
        entries: [BandleLeaderboardEntry]? = nil,
        lastUpdated: String? = nil,
        averageAttempt: Double? = nil,
        perfectScoreCount: Int? = nil,
        attemptDistribution: [String: Int]? = nil,
        isInvalid: Bool? = nil,
        invalidationMessage: String? = nil,
        weekStartDate: String? = nil,
        weekEndDate: String? = nil,
        weekNumber: Int? = nil,
        year: Int? = nil,
        month: Int? = nil,
        monthName: String? = nil
    ) {
        self.date = date
        self.mode = mode
        self.songId = songId
        self.songTitle = songTitle
        self.totalPlayers = totalPlayers
        self.totalPlaysIncludingGuests = totalPlaysIncludingGuests
        self.totalWins = totalWins
        self.totalLosses = totalLosses
        self.winRate = winRate
        self.lossRate = lossRate
        self.entries = entries
        self.lastUpdated = lastUpdated
        self.averageAttempt = averageAttempt
        self.perfectScoreCount = perfectScoreCount
        self.attemptDistribution = attemptDistribution
        self.isInvalid = isInvalid
        self.invalidationMessage = invalidationMessage
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.weekNumber = weekNumber
        self.year = year
        self.month = month
        self.monthName = monthName
    }
}
