#if os(iOS)
import Foundation

nonisolated struct WidgetSong: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var artist: String
    var originalArtists: [String] = []
    var coverArtists: [String] = []
    var duration: Int = 0
    var artworkFilename: String?
}

nonisolated struct WidgetPlaylist: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var songCount: Int = 0
    var isPersonal = false
    var artworkFilename: String?
    var artworkFilenames: [String]? = nil
}

nonisolated struct PlaybackWidgetSnapshot: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var updatedAt = Date()
    var song: WidgetSong?
    var isPlaying = false
    var isRadio = false
    var hasPrevious = false
    var hasNext = false
    var playlistID: String?
    var playlistName: String?
    var isFavorite = false
    var playbackMode = "Original"
    var repeatMode = "off"
    var isShuffled = false
    var queue: [WidgetSong] = []
    var elapsedSeconds: Double? = nil
    var durationSeconds: Double? = nil
    var isBuffering: Bool? = nil

    func elapsed(at date: Date) -> Double {
        let duration = max(0, durationSeconds ?? Double(song?.duration ?? 0))
        let advanced = isPlaying ? max(0, date.timeIntervalSince(updatedAt)) : 0
        return min(duration, max(0, (elapsedSeconds ?? 0) + advanced))
    }
    var playbackInterval: ClosedRange<Date>? {
        let duration = durationSeconds ?? Double(song?.duration ?? 0)
        guard !isRadio, duration > 0, isPlaying else { return nil }
        let start = updatedAt.addingTimeInterval(-max(0, elapsedSeconds ?? 0))
        return start...start.addingTimeInterval(duration)
    }
}

nonisolated struct LibraryWidgetSnapshot: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var updatedAt = Date()
    var recent: [WidgetPlaylist] = []
    var pinned: [WidgetPlaylist] = []
    var saved: [WidgetPlaylist] = []
    var personal: [WidgetPlaylist] = []
    var downloadedCount = 0
    var favoriteCount = 0
    var accountAvailable = false
    var catalogSuggestions: [WidgetPlaylist]? = nil

    var suggestions: [WidgetPlaylist] {
        var seen = Set<String>()
        let favorites = accountAvailable ? [WidgetPlaylist(id: "__favorites__", name: String(localized: "Favorites"), songCount: favoriteCount, isPersonal: true)] : []
        return (favorites + pinned + recent + personal + saved + (catalogSuggestions ?? [])).filter { seen.insert($0.id).inserted }
    }
}

nonisolated struct WidgetSnapshotStore: Sendable {
    // Both bundles carry this value in Info.plist, matching their entitlements.
    static let groupID = Bundle.main.object(forInfoDictionaryKey: "WidgetAppGroupIdentifier") as? String
        ?? "group.org.magnettileman.Twinskaraoke"
    let directory: URL?
    init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)) {
        self.directory = directory
    }
    func readPlayback() -> PlaybackWidgetSnapshot {
        let value: PlaybackWidgetSnapshot? = read("playback.json")
        return value?.schemaVersion == 1 ? value! : PlaybackWidgetSnapshot()
    }
    func readLibrary() -> LibraryWidgetSnapshot {
        let value: LibraryWidgetSnapshot? = read("library.json")
        return value?.schemaVersion == 1 ? value! : LibraryWidgetSnapshot()
    }
    private func read<T: Decodable>(_ name: String) -> T? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    func write(_ value: PlaybackWidgetSnapshot) throws { try write(value, name: "playback.json") }
    func write(_ value: LibraryWidgetSnapshot) throws { try write(value, name: "library.json") }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

nonisolated enum WidgetKinds {
    static let recent = "TwinskaraokeRecentlyPlayed"
    static let nowPlaying = "TwinskaraokeNowPlaying"
    static let radio = "TwinskaraokeLiveRadio"
}
#endif
