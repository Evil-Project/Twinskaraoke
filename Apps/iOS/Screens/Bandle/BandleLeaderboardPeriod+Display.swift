import Foundation

extension BandleLeaderboardPeriod {
    var title: String {
        switch self {
        case .today: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .global: String(localized: "All Time")
        }
    }
}
