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
    let averageTime: Duration?
    let perfectScores: Int?

    init(board: BandleLeaderboard) {
        let wins = board.totalWins
        let losses = board.totalLosses
        let plays = wins.flatMap { wins in losses.map { wins + $0 } }
        let players = board.totalPlaysIncludingGuests ?? plays ?? board.totalPlayers
        self.players = players
        self.wins = wins
        self.losses = losses
        winRate = board.winRate.map { $0 / 100 } ?? Self.fraction(wins, of: players)
        lossRate = board.lossRate.map { $0 / 100 } ?? Self.fraction(losses, of: players)
        averageAttempt = board.averageAttempt
        averageTime = Self.meanTime(of: board.entries ?? [])
        perfectScores = board.perfectScoreCount
    }

    private static func fraction(_ count: Int?, of total: Int?) -> Double? {
        guard let count, let total, total > 0 else { return nil }
        return Double(count) / Double(total)
    }

    private static func meanTime(of entries: [BandleLeaderboardEntry]) -> Duration? {
        let times = entries.compactMap { $0.timeSpent.flatMap(BandleTimeSpan.duration(from:)) }
        guard !times.isEmpty else { return nil }
        return times.reduce(.zero, +) / times.count
    }
}
