import Foundation

nonisolated struct BandleAudioClip: Codable, Equatable, Identifiable, Sendable {
    let attemptNumber: Int?
    let clipLength: Int?
    let audioUrl: String?
    let mode: BandleMode?
    let effect: BandleAudioEffect?
    let sourceClipLength: Int?

    var id: Int { attemptNumber ?? 0 }

    init(
        attemptNumber: Int? = nil,
        clipLength: Int? = nil,
        audioUrl: String? = nil,
        mode: BandleMode? = nil,
        effect: BandleAudioEffect? = nil,
        sourceClipLength: Int? = nil
    ) {
        self.attemptNumber = attemptNumber
        self.clipLength = clipLength
        self.audioUrl = audioUrl
        self.mode = mode
        self.effect = effect
        self.sourceClipLength = sourceClipLength
    }

    var playableURL: URL? {
        guard let audioUrl, !audioUrl.isEmpty else { return nil }
        return URL(string: audioUrl, relativeTo: URL(string: StorageHost.api))?.absoluteURL
    }
}
