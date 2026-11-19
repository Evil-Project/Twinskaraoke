import Foundation

nonisolated extension UITestFixtures {
    static let bandleHistory = [
        BandleHistoryEntry(
            gameID: "bandle-game-2",
            challengeDate: "2026-11-14T00:00:00Z",
            mode: .normal,
            won: true,
            attemptNumber: 2,
            score: 10800,
            timeSpent: "00:01:12",
            dailySong: BandleHistorySong(songTitle: "Hero", artist: "Neuro")
        ),
        BandleHistoryEntry(
            gameID: "bandle-game-1",
            challengeDate: "2026-11-13T00:00:00Z",
            mode: .normal,
            won: false,
            attemptNumber: 6,
            score: 3200,
            timeSpent: "00:03:40",
            dailySong: BandleHistorySong(songTitle: "Cure For Me", artist: "Evil")
        ),
    ]

    static let bandleUserRanks = BandleUserRanks(
        userId: "user-fixture",
        username: "BandleTester",
        dailyRank: 3,
        weeklyRank: 5,
        monthlyRank: 8,
        globalRank: 13,
        currentStreak: 4,
        longestStreak: 8
    )

    static func bandleLeaderboard(for period: BandleLeaderboardPeriod) -> BandleLeaderboard {
        let isDaily = period == .today
        let entries = (1 ... 5).map { rank in
            bandleLeaderboardEntry(rank: rank, period: period)
        }
        let wins: Int? = isDaily ? 35 : nil
        let losses: Int? = isDaily ? 7 : nil
        let dailyWinRate: Double? = isDaily ? 83.3 : nil
        let perfectScores: Int? = isDaily ? 8 : nil
        let distribution: [String: Int]? = isDaily ? ["1": 8, "2": 12, "3": 8, "4": 5, "5": 1, "6": 1] : nil
        let weekNumber: Int? = period == .weekly ? 46 : nil
        let year: Int? = period == .weekly || period == .monthly ? 2026 : nil
        let month: Int? = period == .monthly ? 11 : nil
        let monthName: String? = period == .monthly ? "November" : nil
        return BandleLeaderboard(
            date: "2026-11-15T00:00:00Z",
            mode: .normal,
            totalPlayers: 42,
            totalPlaysIncludingGuests: 45,
            totalWins: wins,
            totalLosses: losses,
            winRate: dailyWinRate,
            entries: entries,
            averageAttempt: 2.4,
            perfectScoreCount: perfectScores,
            attemptDistribution: distribution,
            isInvalid: false,
            weekNumber: weekNumber,
            year: year,
            month: month,
            monthName: monthName
        )
    }

    private static func bandleLeaderboardEntry(rank: Int, period: BandleLeaderboardPeriod) -> BandleLeaderboardEntry {
        var entry = BandleLeaderboardEntry(
            userId: rank == 3 ? bandleUserRanks.userId : "leaderboard-user-\(rank)",
            username: rank == 3 ? "BandleTester" : "Player \(rank)",
            rank: rank,
            score: 12500 - rank * 125,
            totalScore: Int64(50000 - rank * 1000),
            averageAttempt: Double(rank) + 0.5,
            perfectScores: 10 - rank
        )
        switch period {
        case .today:
            entry.attemptNumber = min(rank, 6)
            entry.timeSpent = "00:00:1\(rank)"
            entry.isPerfect = rank == 1
        case .weekly:
            entry.gamesPlayed = 20 - rank
            entry.gamesWon = 18 - rank
            entry.weeklyStreak = 7 - rank
            entry.winRate = Double(90 - rank)
        case .monthly:
            entry.gamesPlayed = 20 - rank
            entry.gamesWon = 18 - rank
            entry.monthlyStreak = 20 - rank
            entry.winRate = Double(90 - rank)
        case .global:
            entry.totalGamesPlayed = 100 - rank
            entry.totalGamesWon = 90 - rank
            entry.currentStreak = 15 - rank
            entry.longestStreak = 30 - rank
            entry.winRate = Double(90 - rank)
        }
        return entry
    }
}
