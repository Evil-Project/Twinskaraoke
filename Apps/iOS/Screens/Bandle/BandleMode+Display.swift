import Foundation

extension BandleMode {
    var title: String {
        switch self {
        case .normal: String(localized: "Normal")
        case .extreme: String(localized: "Extreme")
        }
    }
}
