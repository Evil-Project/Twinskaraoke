import Foundation

nonisolated struct BandleProgress: Decodable, Equatable, Sendable {
    let currentAttemptNumber: Int?
    let attempts: [BandleAttempt]?
    let lastUpdated: String?

    init(currentAttemptNumber: Int? = nil, attempts: [BandleAttempt]? = nil, lastUpdated: String? = nil) {
        self.currentAttemptNumber = currentAttemptNumber
        self.attempts = attempts
        self.lastUpdated = lastUpdated
    }
}
