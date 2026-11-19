import Foundation

/// Today's totals from the daily leaderboard, counted as twinskaraoke.com
/// counts them.
///
/// The leaderboard's `totalPlayers` is only the ranked accounts on the board,
/// while its wins, losses, average attempt and perfect scores include guests.
/// Showing `totalPlayers` next to them gave more wins than players, so the
/// player count comes from every play instead.
nonisolated struct BandleDailyStats: Equatable, Sendable {
    let players: Int?
    let wins: Int?
    let losses: Int?
    /// Fractions of all plays (0...1), ready for `.percent` formatting.
    let winRate: Double?
    let lossRate: Double?
    let averageAttempt: Double?
    /// The mean time the ranked entries took; the server doesn't send one.
    /// Missing when the board holds only some of them.
    let averageTime: Duration?
    let perfectScores: Int?

    /// Minutes and seconds, padded: "01:03". Partial seconds are dropped,
    /// not rounded, as on twinskaraoke.com (63.9 s reads 01:03 there).
    static let timeFormat: Duration.TimeFormatStyle = .time(
        pattern: .minuteSecond(padMinuteToLength: 2, roundFractionalSeconds: .towardZero)
    )

    init(board: BandleLeaderboard) {
        let wins = board.totalWins
        let losses = board.totalLosses
        // Wins and losses can include guests, so a rate needs a total of
        // all plays; the ranked count would let wins exceed 100%.
        let allPlays = board.totalPlaysIncludingGuests ?? wins.flatMap { wins in losses.map { wins + $0 } }
        players = allPlays ?? board.totalPlayers
        self.wins = wins
        self.losses = losses
        winRate = board.winRate.map { $0 / 100 } ?? Self.fraction(wins, of: allPlays)
        lossRate = board.lossRate.map { $0 / 100 } ?? Self.fraction(losses, of: allPlays)
        averageAttempt = board.averageAttempt
        averageTime = Self.meanTime(of: board.entries ?? [], rankedPlayers: board.totalPlayers)
        perfectScores = board.perfectScoreCount
    }

    private static func fraction(_ count: Int?, of total: Int?) -> Double? {
        guard let count, let total, total > 0 else { return nil }
        return Double(count) / Double(total)
    }

    /// The request's `limit` can cut the board off; the top entries' mean
    /// isn't the day's, so a partial board has no average.
    private static func meanTime(of entries: [BandleLeaderboardEntry], rankedPlayers: Int?) -> Duration? {
        if let rankedPlayers, entries.count < rankedPlayers { return nil }
        let times = entries.compactMap { $0.timeSpent.flatMap(BandleTimeSpan.duration(from:)) }
        guard !times.isEmpty else { return nil }
        return times.reduce(.zero, +) / times.count
    }
}
