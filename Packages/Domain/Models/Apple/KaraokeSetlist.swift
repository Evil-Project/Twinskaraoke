import Foundation

/// The setlist of one karaoke stream: a playlist the server flags as a
/// setlist, plus the stream's day and total length.
nonisolated struct KaraokeSetlist: Decodable, Identifiable, Sendable {
    /// Name, artwork and songs, decoded like every other playlist, so a
    /// setlist opens in the playlist screen unchanged.
    let playlist: Playlist
    /// The stream's calendar day: a date without a time, so it reads the
    /// same in every time zone, including after the device changes zones.
    let streamDay: DateComponents?
    /// Total length in seconds.
    let totalDuration: Int?

    var id: String { playlist.id }
    var name: String { playlist.name }

    private enum CodingKeys: String, CodingKey {
        case setListDate, totalDuration
    }

    init(playlist: Playlist, streamDay: DateComponents?, totalDuration: Int?) {
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
            songListDTOs: decoded.songListDTOs,
            isPersonal: decoded.isPersonal
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamDay = (try? container.decodeIfPresent(String.self, forKey: .setListDate))
            .flatMap { Self.day(from: $0) }
        totalDuration = try? container.decodeIfPresent(Int.self, forKey: .totalDuration)
    }

    /// The server sends the day as a timestamp without a time zone, such as
    /// `2026-10-29T00:00:00` or `2025-12-27T20:14:06.4719616`. Only the date
    /// part is read, and it's kept as a year, month and day: an instant would
    /// land on the day before or after in some time zones.
    static func day(from timestamp: String) -> DateComponents? {
        let style = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        guard let date = try? style.parse(String(timestamp.prefix(10))) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return DateComponents(year: parts.year, month: parts.month, day: parts.day)
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

    /// Strict, unlike most payloads here: a response that doesn't match
    /// throws, so a refresh keeps the years already loaded instead of
    /// replacing them with none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            totalCount: container.decode(Int.self, forKey: .totalCount),
            years: container.decode([Int].self, forKey: .years)
        )
    }
}
