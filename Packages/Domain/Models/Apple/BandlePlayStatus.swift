import Foundation

nonisolated struct BandlePlayStatus: Decodable, Equatable, Sendable {
    let userId: String?
    let hasPlayed: Bool?
    let date: String?
    let mode: BandleMode?
    let inProgress: Bool?
    let progress: BandleProgress?

    init(
        userId: String? = nil,
        hasPlayed: Bool? = nil,
        date: String? = nil,
        mode: BandleMode? = nil,
        inProgress: Bool? = nil,
        progress: BandleProgress? = nil
    ) {
        self.userId = userId
        self.hasPlayed = hasPlayed
        self.date = date
        self.mode = mode
        self.inProgress = inProgress
        self.progress = progress
    }
}
