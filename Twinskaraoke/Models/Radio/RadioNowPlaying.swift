import Foundation

struct RadioNowPlaying: Decodable {
    let station: Station
    let listeners: Listeners?
    let nowPlaying: NowPlayingItem?
    let playingNext: NowPlayingItem?
    let songHistory: [HistoryItem]?

    struct Station: Decodable {
        let name: String
        let description: String?
        let listenUrl: String

        enum CodingKeys: String, CodingKey {
            case name, description
            case listenUrl = "listen_url"
        }
    }

    struct Listeners: Decodable {
        let total: Int
        let unique: Int
    }

    struct NowPlayingItem: Decodable {
        let song: SongInfo
    }

    struct HistoryItem: Decodable {
        let song: SongInfo
    }

    struct SongInfo: Decodable {
        let id: String
        let art: String?
        let text: String?
        let artist: String?
        let title: String?
        let customFields: CustomFields?

        enum CodingKeys: String, CodingKey {
            case id, art, text, artist, title
            case customFields = "custom_fields"
        }
    }

    struct CustomFields: Decodable {
        let songID: String?

        enum CodingKeys: String, CodingKey {
            case songID = "songId"
        }
    }

    enum CodingKeys: String, CodingKey {
        case station, listeners
        case nowPlaying = "now_playing"
        case playingNext = "playing_next"
        case songHistory = "song_history"
    }
}

extension RadioNowPlaying.SongInfo {
    var resolvedSongID: String? {
        customFields?.songID
    }

    func toSong(stationID: String) -> Song {
        Song(
            id: resolvedSongID ?? "radio:\(stationID)",
            title: title ?? text ?? "Live Radio",
            duration: 0,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: artist.map { [$0] },
            coverArtists: nil,
            userUploaded: nil
        )
    }
}
