import Foundation

/// The setlist of one karaoke stream: a playlist the server flags as a
/// setlist, plus the stream's day and total length.
nonisolated struct KaraokeSetlist: Decodable, Identifiable, Sendable {
    /// Name, artwork and songs, decoded like every other playlist, so a
    /// setlist opens in the playlist screen unchanged.
    let playlist: Playlist
    /// Midnight at the start of the stream's day, in the current time zone.
    let streamDay: Date?
    /// Total length in seconds.
    let totalDuration: Int?

    var id: String { playlist.id }
    var name: String { playlist.name }

    private enum CodingKeys: String, CodingKey {
        case setListDate, totalDuration
    }

    init(playlist: Playlist, streamDay: Date?, totalDuration: Int?) {
        self.playlist = playlist
        self.streamDay = streamDay
        self.totalDuration = totalDuration
    }

    init(from decoder: Decoder) throws {
        let decoded = try Playlist(from: decoder)
        // Count the songs when the server leaves the count out.
        playlist = decoded.songCount > 0 ? decoded : Playlist(
            id: decoded.id,
            name: decoded.name,
            songCount: decoded.songListDTOs?.count ?? 0,
            media: decoded.media,
            mosaicMedia: decoded.mosaicMedia,
            songListDTOs: decoded.songListDTOs
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamDay = (try? container.decodeIfPresent(String.self, forKey: .setListDate))
            .flatMap { Self.day(from: $0) }
        totalDuration = try? container.decodeIfPresent(Int.self, forKey: .totalDuration)
    }

    /// The server sends the day as a timestamp without a time zone, such as
    /// `2026-10-29T00:00:00` or `2025-12-27T20:14:06.4719616`. Only the date
    /// part is read: treating the timestamp as UTC would move it to the day
    /// before in time zones west of UTC.
    static func day(from timestamp: String, timeZone: TimeZone = .current) -> Date? {
        let style = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
        return try? style.parse(String(timestamp.prefix(10)))
    }
}

/// How many setlists there are and which years they span.
nonisolated struct SetlistStats: Decodable, Equatable, Sendable {
    let totalCount: Int
    /// Newest first.
    let years: [Int]

    private enum CodingKeys: String, CodingKey {
        case totalCount, years
    }

    init(totalCount: Int, years: [Int]) {
        self.totalCount = totalCount
        self.years = Array(Set(years)).sorted(by: >)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            totalCount: (try? container.decodeIfPresent(Int.self, forKey: .totalCount)) ?? 0,
            years: (try? container.decodeIfPresent([Int].self, forKey: .years)) ?? []
        )
    }
}
