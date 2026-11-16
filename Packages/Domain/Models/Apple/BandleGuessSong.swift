import Foundation

nonisolated struct BandleGuessSong: Decodable, Equatable, Identifiable, Sendable {
    let songId: String?
    let title: String?
    let originalArtists: String?
    let coverArtists: String?
    let formattedName: String?

    var id: String { songId ?? formattedName ?? title ?? "" }
    var displayName: String { formattedName ?? title ?? "" }

    init(
        songId: String? = nil,
        title: String? = nil,
        originalArtists: String? = nil,
        coverArtists: String? = nil,
        formattedName: String? = nil
    ) {
        self.songId = songId
        self.title = title
        self.originalArtists = originalArtists
        self.coverArtists = coverArtists
        self.formattedName = formattedName
    }
}
