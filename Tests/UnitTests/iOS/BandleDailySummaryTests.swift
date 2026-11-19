import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Bandle daily summary")
struct BandleDailySummaryTests {
    /// The live `leaderboard/today` response of 2026-11-19, cut to three
    /// entries. `totalPlayers` counts only the ranked accounts, while wins,
    /// losses and the averages include guests.
    private static let today = Data(#"""
        {
          "date": "2026-11-19T00:00:00Z", "mode": 0, "songId": "", "songTitle": "",
          "totalPlayers": 34, "totalPlaysIncludingGuests": 37,
          "totalWins": 35, "totalLosses": 2, "winRate": 94.6, "lossRate": 5.4,
          "averageAttempt": 1.8571428571428572, "perfectScoreCount": 24,
          "attemptDistribution": {"1": 24, "2": 4, "3": 2, "4": 0, "5": 3, "6": 2},
          "isInvalid": false, "invalidationMessage": null,
          "entries": [
            {"userId": "a", "rank": 1, "score": 11939, "attemptNumber": 1, "timeSpent": "00:00:06.1007907", "isPerfect": true},
            {"userId": "b", "rank": 2, "score": 11911, "attemptNumber": 1, "timeSpent": "00:00:08.8531380", "isPerfect": true},
            {"userId": "c", "rank": 3, "score": 9000, "attemptNumber": 5, "timeSpent": "00:03:03.0460713", "isPerfect": false}
          ]
        }
        """#.utf8)

    @Test("Players counts every play, guests included, as the website does")
    func playersIncludeGuests() throws {
        let board = try JSONDecoder().decode(BandleLeaderboard.self, from: Self.today)
        let summary = BandleDailyStats(board: board)

        #expect(summary.players == 37)
        #expect(summary.wins == 35)
        #expect(summary.losses == 2)
        #expect(summary.averageAttempt == 1.8571428571428572)
        #expect(summary.perfectScores == 24)
    }

    @Test("Win and loss rates are fractions of all plays")
    func ratesAreFractions() throws {
        let board = try JSONDecoder().decode(BandleLeaderboard.self, from: Self.today)
        let summary = BandleDailyStats(board: board)

        let winRate = try #require(summary.winRate)
        let lossRate = try #require(summary.lossRate)
        #expect(abs(winRate - 0.946) < 1e-9)
        #expect(abs(lossRate - 0.054) < 1e-9)
    }

    @Test("Average time is the mean of the entries' time spent")
    func averageTimeFromEntries() throws {
        // The three entries of the live response, as a complete board.
        let board = BandleLeaderboard(
            totalPlayers: 3,
            entries: [
                BandleLeaderboardEntry(userId: "a", timeSpent: "00:00:06.1007907"),
                BandleLeaderboardEntry(userId: "b", timeSpent: "00:00:08.8531380"),
                BandleLeaderboardEntry(userId: "c", timeSpent: "00:03:03.0460713"),
            ]
        )
        let summary = BandleDailyStats(board: board)

        let time = try #require(summary.averageTime).components
        let seconds = Double(time.seconds) + Double(time.attoseconds) / 1e18
        #expect(abs(seconds - 66) < 0.001)
    }

    @Test("Without the guest total, players and rates come from wins and losses")
    func fallsBackToWinsAndLosses() {
        let board = BandleLeaderboard(totalPlayers: 3, totalWins: 3, totalLosses: 1)
        let summary = BandleDailyStats(board: board)

        #expect(summary.players == 4)
        #expect(summary.winRate == 0.75)
        #expect(summary.lossRate == 0.25)
    }

    @Test("Rates aren't divided by the ranked-only player count")
    func noRateFromRankedPlayers() {
        // Without a total of all plays, wins can include guests the ranked
        // count leaves out: 4 wins over 3 ranked players would read 133%.
        let board = BandleLeaderboard(totalPlayers: 3, totalWins: 4)
        let summary = BandleDailyStats(board: board)

        #expect(summary.players == 3)
        #expect(summary.winRate == nil)
        #expect(summary.lossRate == nil)
    }

    @Test("A board cut off by the request limit leaves the average time out")
    func noAverageTimeFromPartialBoard() {
        // Only the top entries came back, so their mean isn't the day's.
        let board = BandleLeaderboard(
            totalPlayers: 150,
            totalPlaysIncludingGuests: 160,
            entries: [
                BandleLeaderboardEntry(userId: "a", timeSpent: "00:00:06"),
                BandleLeaderboardEntry(userId: "b", timeSpent: "00:00:08"),
            ]
        )

        #expect(BandleDailyStats(board: board).averageTime == nil)
    }

    @Test("Entries without a readable time leave the average time out")
    func noAverageTimeWithoutTimes() {
        let board = BandleLeaderboard(
            totalPlaysIncludingGuests: 1,
            entries: [BandleLeaderboardEntry(userId: "a", timeSpent: "not a span")]
        )

        #expect(BandleDailyStats(board: board).averageTime == nil)
    }
}
