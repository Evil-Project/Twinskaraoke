import CryptoKit
import Foundation

/// Where Home's top picks came from: setlists, or public playlists when there
/// were no setlists. Paging continues from the same source.
nonisolated enum HomeTopPicksSource: String, Codable, Sendable {
    case setlists
    case publicPlaylists
}

/// What a `KaraokeSetlist` is rebuilt from. The setlist itself only decodes
/// the server's shape, so it can't be written back as it came.
nonisolated struct CachedSetlist: Codable, Sendable {
    let playlist: Playlist
    let streamDay: DateComponents?
    let totalDuration: Int?

    init(_ setlist: KaraokeSetlist) {
        playlist = setlist.playlist
        streamDay = setlist.streamDay
        totalDuration = setlist.totalDuration
    }

    var setlist: KaraokeSetlist {
        KaraokeSetlist(playlist: playlist, streamDay: streamDay, totalDuration: totalDuration)
    }
}

/// The public shelves of Home and New, as the API sent them. A shelf that is
/// absent wasn't saved; a save keeps the stored copy of every absent shelf.
nonisolated struct HomeFeedSnapshot: Codable, Sendable {
    static let currentVersion = 1

    var version = Self.currentVersion
    var savedAt: Date
    /// The API the songs' media paths belong to. A host override (the China
    /// mirrors) makes the snapshot unusable.
    var apiHost: String
    var trending: [Song]?
    var newReleases: [Song]?
    /// The first page only: saved top picks never page.
    var topPicks: [Playlist]?
    var topPicksSource: HomeTopPicksSource?
    var latestSetlist: CachedSetlist?

    init(
        savedAt: Date = Date(),
        apiHost: String = StorageHost.api,
        trending: [Song]? = nil,
        newReleases: [Song]? = nil,
        topPicks: [Playlist]? = nil,
        topPicksSource: HomeTopPicksSource? = nil,
        latestSetlist: CachedSetlist? = nil
    ) {
        self.savedAt = savedAt
        self.apiHost = apiHost
        self.trending = trending
        self.newReleases = newReleases
        self.topPicks = topPicks
        self.topPicksSource = topPicksSource
        self.latestSetlist = latestSetlist
    }

    var isEmpty: Bool {
        trending == nil && newReleases == nil && topPicks == nil && latestSetlist == nil
    }
}

/// One account's "Made for You", kept in its own file.
nonisolated struct HomeSuggestionsSnapshot: Codable, Sendable {
    var version = HomeFeedSnapshot.currentVersion
    var savedAt: Date
    var apiHost: String
    var songs: [Song]

    init(savedAt: Date = Date(), apiHost: String = StorageHost.api, songs: [Song]) {
        self.savedAt = savedAt
        self.apiHost = apiHost
        self.songs = songs
    }
}

/// The last Home feed that loaded, kept so Home and New have something to
/// show when a load gets nothing back (no network).
///
/// Only content is stored: songs and playlists as the API sent them, never a
/// token, header or account name. Suggestions are per account; the file name
/// carries a hash of the account ID, not the ID itself.
nonisolated struct HomeFeedStore: Sendable {
    var loadPublic: @Sendable () async -> HomeFeedSnapshot?
    /// Merges the snapshot's shelves into the stored one and writes it.
    var savePublic: @Sendable (_ snapshot: HomeFeedSnapshot) async -> Void
    var loadSuggestions: @Sendable (_ account: String) async -> HomeSuggestionsSnapshot?
    var saveSuggestions: @Sendable (_ account: String, _ snapshot: HomeSuggestionsSnapshot) async -> Void

    static let maximumAge: TimeInterval = 30 * 24 * 60 * 60
    static let maximumFileSize = 1_000_000
    /// Accounts whose "Made for You" is kept; the least recently saved go.
    static let suggestionFileLimit = 4

    static let live = disk(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeFeed", isDirectory: true)
    )

    static let disabled = HomeFeedStore(
        loadPublic: { nil },
        savePublic: { _ in },
        loadSuggestions: { _ in nil },
        saveSuggestions: { _, _ in }
    )

    static func publicFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("home-feed.v\(HomeFeedSnapshot.currentVersion).json")
    }

    static func suggestionsFileURL(in directory: URL, account: String) -> URL {
        let digest = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(
            "home-suggestions.v\(HomeFeedSnapshot.currentVersion).\(digest).json"
        )
    }

    static func disk(directory: URL, apiHost: @escaping @Sendable () -> String = { StorageHost.api }) -> HomeFeedStore {
        let disk = HomeFeedDisk(directory: directory, apiHost: apiHost)
        return HomeFeedStore(
            loadPublic: { await disk.run { disk.readPublic() } },
            savePublic: { snapshot in await disk.run { disk.writePublic(snapshot) } },
            loadSuggestions: { account in await disk.run { disk.readSuggestions(account: account) } },
            saveSuggestions: { account, snapshot in
                await disk.run { disk.writeSuggestions(snapshot, account: account) }
            }
        )
    }

    /// Applies the same filtering and merging as the disk store, without
    /// files. For tests.
    static func inMemory() -> HomeFeedStore {
        let memory = HomeFeedMemory()
        return HomeFeedStore(
            loadPublic: { await memory.publicSnapshot },
            savePublic: { snapshot in await memory.savePublic(snapshot) },
            loadSuggestions: { account in await memory.suggestions[account] },
            saveSuggestions: { account, snapshot in await memory.saveSuggestions(snapshot, account: account) }
        )
    }

    // MARK: - Rules shared by both stores

    /// Without stream placeholders; a list left empty becomes absent.
    static func sanitized(_ snapshot: HomeFeedSnapshot) -> HomeFeedSnapshot {
        var result = snapshot
        result.trending = withoutPlaceholders(snapshot.trending)
        result.newReleases = withoutPlaceholders(snapshot.newReleases)
        result.topPicks = snapshot.topPicks.map { $0.map(withoutPlaceholders) }.flatMap { $0.isEmpty ? nil : $0 }
        result.topPicksSource = result.topPicks == nil ? nil : snapshot.topPicksSource
        result.latestSetlist = snapshot.latestSetlist.flatMap { cached in
            let playlist = withoutPlaceholders(cached.playlist)
            guard playlist.songListDTOs != nil else { return nil }
            return CachedSetlist(KaraokeSetlist(
                playlist: playlist,
                streamDay: cached.streamDay,
                totalDuration: cached.totalDuration
            ))
        }
        return result
    }

    /// `update`'s shelves over `stored`'s; top picks keep their source.
    static func merged(_ update: HomeFeedSnapshot, over stored: HomeFeedSnapshot?) -> HomeFeedSnapshot {
        guard let stored else { return update }
        var result = update
        result.trending = update.trending ?? stored.trending
        result.newReleases = update.newReleases ?? stored.newReleases
        if update.topPicks == nil {
            result.topPicks = stored.topPicks
            result.topPicksSource = stored.topPicksSource
        }
        result.latestSetlist = update.latestSetlist ?? stored.latestSetlist
        return result
    }

    static func withoutPlaceholders(_ songs: [Song]?) -> [Song]? {
        guard let filtered = songs?.filter({ !KaraokeAPIClient.isStreamPlaceholder($0) }),
              !filtered.isEmpty
        else { return nil }
        return filtered
    }

    private static func withoutPlaceholders(_ playlist: Playlist) -> Playlist {
        playlist.replacingSongs(withoutPlaceholders(playlist.songListDTOs))
    }
}

nonisolated extension Playlist {
    /// The same playlist carrying `songs`; the count stays the server's.
    func replacingSongs(_ songs: [Song]?) -> Playlist {
        Playlist(
            id: id,
            name: name,
            songCount: songCount,
            media: media,
            mosaicMedia: mosaicMedia,
            songListDTOs: songs,
            isPersonal: isPersonal
        )
    }
}

// MARK: - Disk

/// The files behind `HomeFeedStore.disk`. Every method runs on `queue`, one at
/// a time, so a save's read-merge-write can't interleave with another.
private nonisolated final class HomeFeedDisk: Sendable {
    let directory: URL
    let apiHost: @Sendable () -> String
    private let queue = DispatchQueue(label: "HomeFeedStore", qos: .utility)

    init(directory: URL, apiHost: @escaping @Sendable () -> String) {
        self.directory = directory
        self.apiHost = apiHost
    }

    func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: Public shelves

    func readPublic() -> HomeFeedSnapshot? {
        let url = HomeFeedStore.publicFileURL(in: directory)
        guard let snapshot = read(HomeFeedSnapshot.self, at: url) else { return nil }
        guard isUsable(version: snapshot.version, savedAt: snapshot.savedAt, apiHost: snapshot.apiHost) else {
            discard(url, reason: "out of date")
            return nil
        }
        return snapshot
    }

    func writePublic(_ update: HomeFeedSnapshot) {
        let update = HomeFeedStore.sanitized(update)
        guard !update.isEmpty else { return }
        var snapshot = HomeFeedStore.merged(update, over: readPublic())
        guard var data = encode(snapshot) else { return }
        if data.count > HomeFeedStore.maximumFileSize, let picks = snapshot.topPicks {
            snapshot.topPicks = picks.map { $0.replacingSongs(nil) }
            guard let smaller = encode(snapshot) else { return }
            data = smaller
        }
        guard data.count <= HomeFeedStore.maximumFileSize else {
            DebugLogger.log("Home feed not saved: \(data.count) bytes is over the limit", category: .cache)
            return
        }
        write(data, to: HomeFeedStore.publicFileURL(in: directory))
    }

    // MARK: Suggestions

    func readSuggestions(account: String) -> HomeSuggestionsSnapshot? {
        let url = HomeFeedStore.suggestionsFileURL(in: directory, account: account)
        guard let snapshot = read(HomeSuggestionsSnapshot.self, at: url) else { return nil }
        guard isUsable(version: snapshot.version, savedAt: snapshot.savedAt, apiHost: snapshot.apiHost) else {
            discard(url, reason: "out of date")
            return nil
        }
        return snapshot
    }

    func writeSuggestions(_ snapshot: HomeSuggestionsSnapshot, account: String) {
        guard let songs = HomeFeedStore.withoutPlaceholders(snapshot.songs) else { return }
        var snapshot = snapshot
        snapshot.songs = songs
        guard let data = encode(snapshot) else { return }
        guard data.count <= HomeFeedStore.maximumFileSize else {
            DebugLogger.log("Made for You not saved: \(data.count) bytes is over the limit", category: .cache)
            return
        }
        write(data, to: HomeFeedStore.suggestionsFileURL(in: directory, account: account))
        pruneSuggestions()
    }

    /// Keeps the files of the accounts that saved most recently.
    private func pruneSuggestions() {
        let manager = FileManager.default
        let prefix = "home-suggestions."
        guard let urls = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let files = urls
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .map { url in
                (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
        for (url, _) in files.dropFirst(HomeFeedStore.suggestionFileLimit) {
            try? manager.removeItem(at: url)
        }
    }

    // MARK: Files

    private func isUsable(version: Int, savedAt: Date, apiHost: String) -> Bool {
        version == HomeFeedSnapshot.currentVersion
            && apiHost == self.apiHost()
            && Date().timeIntervalSince(savedAt) <= HomeFeedStore.maximumAge
    }

    private func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            discard(url, reason: "unreadable: \(error)")
            return nil
        }
    }

    private func encode(_ value: some Encodable) -> Data? {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            DebugLogger.log("Home feed encode failed: \(error)", category: .cache)
            return nil
        }
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            DebugLogger.log("Home feed write failed: \(error)", category: .cache)
        }
    }

    private func discard(_ url: URL, reason: String) {
        DebugLogger.log("Saved Home feed discarded (\(url.lastPathComponent)): \(reason)", category: .cache)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Memory

private actor HomeFeedMemory {
    private(set) var publicSnapshot: HomeFeedSnapshot?
    private(set) var suggestions: [String: HomeSuggestionsSnapshot] = [:]

    func savePublic(_ update: HomeFeedSnapshot) {
        let update = HomeFeedStore.sanitized(update)
        guard !update.isEmpty else { return }
        publicSnapshot = HomeFeedStore.merged(update, over: publicSnapshot)
    }

    func saveSuggestions(_ snapshot: HomeSuggestionsSnapshot, account: String) {
        guard let songs = HomeFeedStore.withoutPlaceholders(snapshot.songs) else { return }
        var snapshot = snapshot
        snapshot.songs = songs
        suggestions[account] = snapshot
    }
}
