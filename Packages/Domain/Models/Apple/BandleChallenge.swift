import Foundation

nonisolated struct BandleChallenge: Decodable, Equatable, Sendable {
    let id: String?
    let date: String?
    let totalPlays: Int?
    let totalWins: Int?
    let averageAttempt: Double?
    let winRate: Double?
    let isInvalid: Bool?
    let invalidationMessage: String?
    let mode: BandleMode?
    let audioClips: [BandleAudioClip]?
    let replaySongId: String?

    init(
        id: String? = nil,
        date: String? = nil,
        totalPlays: Int? = nil,
        totalWins: Int? = nil,
        averageAttempt: Double? = nil,
        winRate: Double? = nil,
        isInvalid: Bool? = nil,
        invalidationMessage: String? = nil,
        mode: BandleMode? = nil,
        audioClips: [BandleAudioClip]? = nil,
        replaySongId: String? = nil
    ) {
        self.id = id
        self.date = date
        self.totalPlays = totalPlays
        self.totalWins = totalWins
        self.averageAttempt = averageAttempt
        self.winRate = winRate
        self.isInvalid = isInvalid
        self.invalidationMessage = invalidationMessage
        self.mode = mode
        self.audioClips = audioClips
        self.replaySongId = replaySongId
    }
}
