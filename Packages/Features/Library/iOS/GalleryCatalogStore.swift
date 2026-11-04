import Foundation

/// The Art Gallery's artist catalogue, kept between visits and launches.
///
/// `GET /api/media/artists?loadArts=true` returns every artist with every
/// artwork (about 1.5 MB compressed, 7.8 MB of JSON) and sends no cache
/// headers. Without this the gallery downloaded all of it each time it
/// opened, and showed nothing offline. Decoding and file I/O run on this
/// actor, off the main thread.
actor GalleryCatalogStore {
    static let shared = GalleryCatalogStore(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArtGallery", isDirectory: true)
    )

    /// How long a saved catalogue counts as current. An older one is still
    /// shown, and replaced once a new download arrives.
    static let maxAge: TimeInterval = 12 * 60 * 60

    nonisolated struct Snapshot: Codable, Sendable {
        /// Tells a view which catalogue it is showing, even when two were
        /// saved within the same second.
        let id: UUID
        let savedAt: Date
        let artists: [GalleryArtist]
    }

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var memory: Snapshot?
    private var didReadDisk = false
    private var refreshTask: Task<Snapshot, Error>?

    init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        fileURL = directory.appendingPathComponent("artists.json")
        self.now = now
    }

    /// The saved catalogue: from memory, or from disk the first time.
    func cached() -> Snapshot? {
        if memory == nil, !didReadDisk {
            didReadDisk = true
            memory = (try? Data(contentsOf: fileURL))
                .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        }
        return memory
    }

    nonisolated func isCurrent(_ snapshot: Snapshot) -> Bool {
        let age = now().timeIntervalSince(snapshot.savedAt)
        return age >= 0 && age < Self.maxAge
    }

    /// Downloads, filters and saves a new catalogue. A caller that arrives
    /// while a download is running shares it, so two gallery screens neither
    /// download twice nor let an older response overwrite a newer one.
    func refresh(using download: @escaping @Sendable () async throws -> Data) async throws -> Snapshot {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { () throws -> Snapshot in
            let data = try await download()
            return try self.save(data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// Keeps the artists that have artwork, most artworks first, and saves
    /// them in memory and on disk.
    private func save(_ data: Data) throws -> Snapshot {
        let artists = try JSONDecoder().decode([GalleryArtist].self, from: data)
            .filter { ($0.arts?.count ?? 0) > 0 }
            .sorted { ($0.arts?.count ?? 0) > ($1.arts?.count ?? 0) }
        let snapshot = Snapshot(id: UUID(), savedAt: now(), artists: artists)
        memory = snapshot
        didReadDisk = true
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            // This session still shows the new catalogue; only a later launch
            // without network goes without it.
            DebugLogger.log("Couldn't save the Art Gallery catalogue: \(error)", category: .cache)
        }
        return snapshot
    }
}
