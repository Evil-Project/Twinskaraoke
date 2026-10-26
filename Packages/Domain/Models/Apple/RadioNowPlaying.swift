import Foundation
nonisolated enum RadioStation {
    static let id = "neuro_21"

    static let metadataURL = URL(
        string: "https://radio.twinskaraoke.com/api/nowplaying_static/\(id).json"
    )!
}

nonisolated struct RadioNowPlaying: Decodable, Sendable {
    let station: Station
    let listeners: Listeners?
    let nowPlaying: NowPlayingItem?
    let playingNext: NowPlayingItem?
    let songHistory: [HistoryItem]?

    struct Station: Decodable, Sendable {
        let name: String
        let description: String?
        let listenUrl: String

        enum CodingKeys: String, CodingKey {
            case name, description
            case listenUrl = "listen_url"
        }
    }

    struct Listeners: Decodable, Sendable {
        let total: Int
        let unique: Int
    }

    struct NowPlayingItem: Decodable, Sendable {
        let song: SongInfo
    }

    struct HistoryItem: Decodable, Sendable {
        let song: SongInfo
    }

    struct SongInfo: Decodable, Sendable {
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

    struct CustomFields: Decodable, Sendable {
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

// Listener data is optional station metadata. A bad count must not discard
// an otherwise valid song or prevent the app from starting the station.
nonisolated extension RadioNowPlaying {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        station = try values.decode(Station.self, forKey: .station)
        listeners = try? values.decode(Listeners.self, forKey: .listeners)
        nowPlaying = try values.decodeIfPresent(NowPlayingItem.self, forKey: .nowPlaying)
        playingNext = try values.decodeIfPresent(NowPlayingItem.self, forKey: .playingNext)
        songHistory = try values.decodeIfPresent([HistoryItem].self, forKey: .songHistory)
    }
}
nonisolated extension RadioNowPlaying.Listeners {
    private enum CodingKeys: String, CodingKey { case total, unique }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        total = try values.decode(Int.self, forKey: .total)
        guard total >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .total, in: values, debugDescription: "Negative listener count")
        }
        unique = (try? values.decode(Int.self, forKey: .unique)) ?? 0
    }
}
#if !WIDGET_EXTENSION

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

#endif
