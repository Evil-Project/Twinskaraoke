#if os(iOS)
import Foundation

nonisolated struct WidgetRadioSnapshot: Codable, Sendable, Equatable {
    var schemaVersion = 1
    var title = "Twinskaraoke Radio"
    var artist = ""
    var artworkFilename: String?
    var artworkURL: URL?
    var listeners: Int?
    /// Only a successful metadata decode advances this timestamp.
    var fetchedAt: Date?
    var isValid: Bool {
        schemaVersion == 1 && (listeners.map { $0 >= 0 } ?? true)
        && (fetchedAt.map { $0.timeIntervalSince1970.isFinite && $0 <= Date().addingTimeInterval(60) } ?? true)
    }

    init() {}
    init(metadata: RadioNowPlaying, fetchedAt: Date) {
        let song = metadata.nowPlaying?.song
        title = Self.nonempty(song?.title) ?? Self.nonempty(song?.text) ?? metadata.station.name
        artist = Self.nonempty(song?.artist) ?? ""
        artworkURL = song?.art.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }
        listeners = metadata.listeners?.total
        self.fetchedAt = fetchedAt
    }
    private static func nonempty(_ text: String?) -> String? {
        text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
    /// Compatibility wrapper for existing callers. Invalid payloads have no timestamp.
    static func decode(_ data: Data, fetchedAt: Date = .now) -> (snapshot: Self, artworkURL: URL?) {
        guard let metadata = try? JSONDecoder().decode(RadioNowPlaying.self, from: data) else { return (Self(), nil) }
        let snapshot = Self(metadata: metadata, fetchedAt: fetchedAt)
        return (snapshot, snapshot.artworkURL)
    }
    func hasSameContent(as other: Self) -> Bool {
        var lhs = self, rhs = other
        lhs.fetchedAt = nil; rhs.fetchedAt = nil
        return lhs == rhs
    }
}

nonisolated enum WidgetRadioRepository {
    // WidgetKit treats this as a request, not a real-time polling guarantee.
    static let refreshInterval: TimeInterval = 900
    static func fetch(store: WidgetSnapshotStore = WidgetSnapshotStore(), session: URLSession = .shared) async -> WidgetRadioSnapshot {
        var request = URLRequest(url: RadioStation.metadataURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return store.readRadio() }
        let result = WidgetRadioSnapshot.decode(data)
        guard result.snapshot.fetchedAt != nil else { return store.readRadio() }
        return await cache(result.snapshot, store: store, session: session)
    }

    /// The app and extension publish through the same cache path. A late network
    /// response cannot overwrite a newer successful app fetch.
    static func cache(_ snapshot: WidgetRadioSnapshot, store: WidgetSnapshotStore = WidgetSnapshotStore(), session: URLSession = .shared) async -> WidgetRadioSnapshot {
        var snapshot = snapshot
        let previous = store.readRadio()
        if let url = snapshot.artworkURL {
            let artwork = WidgetArtworkStore(directory: store.directory)
            let filename = WidgetArtworkStore.filename(for: url.absoluteString)
            if let file = artwork.url(for: filename), FileManager.default.fileExists(atPath: file.path) {
                snapshot.artworkFilename = filename
            } else if let original = WidgetArtworkStore.originalURL(for: url) {
                var request = URLRequest(url: original)
                request.timeoutInterval = 5
                if let (data, response) = try? await session.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8_000_000 {
                    snapshot.artworkFilename = try? artwork.store(data, key: url.absoluteString)
                }
            }
            // Keep artwork only when it belongs to the same track/URL.
            if snapshot.artworkFilename == nil, previous.artworkURL == url {
                snapshot.artworkFilename = previous.artworkFilename
            }
        }
        let latest = store.readRadio()
        guard (latest.fetchedAt ?? .distantPast) <= (snapshot.fetchedAt ?? .distantPast) else { return latest }
        try? store.write(snapshot)
        return snapshot
    }
}
#endif
