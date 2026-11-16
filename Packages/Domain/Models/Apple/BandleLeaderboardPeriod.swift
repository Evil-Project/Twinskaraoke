import Foundation

nonisolated enum BandleLeaderboardPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case weekly
    case monthly
    case global

    var id: String { rawValue }

    var rankKeyPath: KeyPath<BandleUserRanks, Int?> {
        switch self {
        case .today: \.dailyRank
        case .weekly: \.weeklyRank
        case .monthly: \.monthlyRank
        case .global: \.globalRank
        }
    }
}
