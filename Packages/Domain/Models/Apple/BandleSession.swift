import Foundation

nonisolated struct BandleSession: Decodable, Equatable, Sendable {
    let startedAt: String?
    let date: String?
    let mode: BandleMode?

    init(startedAt: String? = nil, date: String? = nil, mode: BandleMode? = nil) {
        self.startedAt = startedAt
        self.date = date
        self.mode = mode
    }
}
