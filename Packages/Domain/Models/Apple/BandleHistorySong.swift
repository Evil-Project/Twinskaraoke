import Foundation

nonisolated struct BandleHistorySong: Decodable, Sendable {
    let id: String?
    let date: String?
    let songId: String?
    let songTitle: String?
    let artist: String?
    let coverArtist: String?
    let audioUrl: String?
    let mode: BandleMode?

    init(
        id: String? = nil,
        date: String? = nil,
        songId: String? = nil,
        songTitle: String? = nil,
        artist: String? = nil,
        coverArtist: String? = nil,
        audioUrl: String? = nil,
        mode: BandleMode? = nil
    ) {
        self.id = id
        self.date = date
        self.songId = songId
        self.songTitle = songTitle
        self.artist = artist
        self.coverArtist = coverArtist
        self.audioUrl = audioUrl
        self.mode = mode
    }
}
