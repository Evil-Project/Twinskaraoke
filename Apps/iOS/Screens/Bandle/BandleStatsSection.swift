import Foundation

enum BandleStatsSection: String, CaseIterable, Identifiable {
    case leaderboard
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leaderboard: String(localized: "Leaderboard")
        case .history: String(localized: "History")
        }
    }
}
