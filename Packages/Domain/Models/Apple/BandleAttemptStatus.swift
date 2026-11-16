import Foundation

nonisolated enum BandleAttemptStatus: Int, Codable, Sendable {
    case correct = 0
    case incorrect = 1
    case skipped = 2
}
