import Foundation

extension BandleAttemptStatus {
    var title: String {
        switch self {
        case .correct: String(localized: "Correct")
        case .incorrect: String(localized: "Incorrect")
        case .skipped: String(localized: "Skipped")
        }
    }

    var systemImage: String {
        switch self {
        case .correct: "checkmark"
        case .incorrect: "xmark"
        case .skipped: "forward.fill"
        }
    }
}
