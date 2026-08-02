import Foundation
import SDWebImageSwiftUI
import Observation

@MainActor
@Observable
final class CacheManager {
    static let shared = CacheManager()

    nonisolated static let imageCacheLimit: UInt64 = 2 * 1024 * 1024 * 1024
    nonisolated static let musicCacheLimit: UInt64 = 4 * 1024 * 1024 * 1024
    // Lyrics are KB-sized JSON documents; a few MB already holds thousands.
    nonisolated static let lyricsCacheLimit: UInt64 = 64 * 1024 * 1024
    nonisolated static let maxCacheAge: TimeInterval = 6 * 30 * 24 * 3600

    private(set) var imageCacheSize: UInt64 = 0
    private(set) var musicCacheSize: UInt64 = 0
    private(set) var lyricsCacheSize: UInt64 = 0

    private let fm = FileManager.default
    @ObservationIgnored private var sizeRefreshTask: Task<Void, Never>?

    // Maintenance walks entire cache directories (music cache can hold
    // gigabytes across hundreds of folders). That file I/O must stay off the
    // main thread; the serial queue also keeps passes from overlapping.
    private nonisolated static let maintenanceQueue = DispatchQueue(
        label: "nk.cacheMaintenance", qos: .utility
    )

    // Debounce state for the per-transition/per-save enforcement passes.
    // Only touched on the serial maintenanceQueue.
    private nonisolated static let enforcementDebounceInterval: TimeInterval = 60
    // Written on the serial maintenance queue, never read by a view:
    // observation-tracking these would route background writes through the
    // registrar and break the nonisolated(unsafe) contract.
    @ObservationIgnored private nonisolated(unsafe) var lastMusicEnforcementAt: Date?
    private nonisolated(unsafe) static var lastMusicCommitAt: Date?
    // Written on the serial maintenance queue, never read by a view:
    // observation-tracking these would route background writes through the
    // registrar and break the nonisolated(unsafe) contract.
    @ObservationIgnored private nonisolated(unsafe) var lastMusicCacheSize: UInt64?
    // Written on the serial maintenance queue, never read by a view:
    // observation-tracking these would route background writes through the
    // registrar and break the nonisolated(unsafe) contract.
    @ObservationIgnored private nonisolated(unsafe) var lastLyricsEnforcementAt: Date?
    // Written on the serial maintenance queue, never read by a view:
    // observation-tracking these would route background writes through the
    // registrar and break the nonisolated(unsafe) contract.
    @ObservationIgnored private nonisolated(unsafe) var lastLyricsCacheSize: UInt64?

    private init() {
        let directories = Self.directories
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let pruned = pruneExpiredEntriesBlocking(directories: directories)
            DebugLogger.log("Pruned \(pruned) expired cache entries", category: .cache)
            // The enforcement passes already measure each tree; reuse their
            // sizes instead of walking every cache directory a second time.
            let image = enforceImageCacheLimitsBlocking()
            let music = enforceMusicCacheLimitsBlocking(musicDirectory: directories.music, excluding: [])
            let lyrics = enforceLyricsCacheLimitsBlocking(lyricsDirectory: directories.lyrics)
            publishSizes((image: image, music: music, lyrics: lyrics))
            DebugLogger.log("CacheManager initialized", category: .cache)
        }
    }

    private static var directories: (music: URL, lyrics: URL) {
        (AudioPlayerManager.audioCacheDir, LyricsCacheStore.cacheDirectory)
    }

    func enforceAllLimits() {
        let directories = Self.directories
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let image = enforceImageCacheLimitsBlocking()
            let music = enforceMusicCacheLimitsBlocking(musicDirectory: directories.music, excluding: [])
            let lyrics = enforceLyricsCacheLimitsBlocking(lyricsDirectory: directories.lyrics)
            publishSizes((image: image, music: music, lyrics: lyrics))
        }
    }

    func refreshSizes() {
        sizeRefreshTask?.cancel()
        sizeRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.sizeRefreshTask = nil
            let directories = Self.directories
            Self.maintenanceQueue.async { [weak self] in
                guard let self else { return }
                publishSizes(computeSizesBlocking(directories: directories))
            }
        }
    }

    func enforceImageCacheLimits() {
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let size = enforceImageCacheLimitsBlocking()
            publishSizes((image: size, music: nil, lyrics: nil))
        }
    }

    func enforceMusicCacheLimits(excluding songIDs: Set<String> = []) {
        let musicDirectory = AudioPlayerManager.audioCacheDir
        let protectedStorageKeys = SongStorageKey.components(for: songIDs)
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let size = enforceMusicCacheLimitsBlocking(
                musicDirectory: musicDirectory,
                excluding: protectedStorageKeys
            )
            publishSizes((image: nil, music: size, lyrics: nil))
        }
    }

    func enforceLyricsCacheLimits() {
        let lyricsDirectory = LyricsCacheStore.cacheDirectory
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let size = enforceLyricsCacheLimitsBlocking(lyricsDirectory: lyricsDirectory)
            publishSizes((image: nil, music: nil, lyrics: size))
        }
    }

    func pruneExpiredEntries() {
        let directories = Self.directories
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let pruned = pruneExpiredEntriesBlocking(directories: directories)
            DebugLogger.log("Pruned \(pruned) expired cache entries", category: .cache)
            publishSizes(computeSizesBlocking(directories: directories))
        }
    }

    func recordAccess(for url: URL) {
        // touch() performs two synchronous setAttributes calls; keep them off
        // the caller's thread (usually main, once per play).
        Self.maintenanceQueue.async {
            AudioCacheStore.touch(url)
        }
    }

    /// Marks that a file was committed to the music cache, so the debounced
    /// enforcement pass knows the tree changed since its last run.
    nonisolated static func noteMusicCacheCommit() {
        maintenanceQueue.async {
            lastMusicCommitAt = Date()
        }
    }

    func totalImageCacheSize() -> UInt64 {
        imageCacheSize
    }

    func totalMusicCacheSize() -> UInt64 {
        musicCacheSize
    }

    func totalLyricsCacheSize() -> UInt64 {
        lyricsCacheSize
    }

    func clearImageCache() {
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                FallbackArtProvider.shared.resetBindings()
                imageCacheSize = 0
                DebugLogger.log("Image cache cleared", category: .cache)
            }
        }
    }

    func clearMusicCache() {
        let dir = AudioPlayerManager.audioCacheDir
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            removeAllFiles(in: dir)
            // The tree changed outside an enforcement pass; drop the debounced
            // size/run markers so the next pass re-measures instead of
            // republishing the pre-clear size.
            lastMusicEnforcementAt = nil
            lastMusicCacheSize = nil
            Self.lastMusicCommitAt = Date()
            let remainingSize = measuredDirectorySize(at: dir)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let remainingSize else {
                    DebugLogger.log("Could not verify music cache deletion", category: .cache)
                    return
                }
                musicCacheSize = remainingSize
                DebugLogger.log(
                    remainingSize == 0
                        ? "Music cache cleared"
                        : "Music cache clear incomplete: \(formatBytes(remainingSize)) remains",
                    category: .cache
                )
            }
        }
    }

    func clearLyricsCache() {
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            LyricsCacheStore.clear()
            // Same as clearMusicCache: drop the debounced markers so the next
            // enforcement pass re-measures instead of republishing stale sizes.
            lastLyricsEnforcementAt = nil
            lastLyricsCacheSize = nil
            let remainingSize = measuredDirectorySize(at: LyricsCacheStore.cacheDirectory)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let remainingSize else {
                    DebugLogger.log("Could not verify lyrics cache deletion", category: .cache)
                    return
                }
                lyricsCacheSize = remainingSize
                DebugLogger.log(
                    remainingSize == 0
                        ? "Lyrics cache cleared"
                        : "Lyrics cache clear incomplete: \(formatBytes(remainingSize)) remains",
                    category: .cache
                )
            }
        }
    }

    func formattedImageCacheSize() -> String {
        formatBytes(imageCacheSize)
    }

    func formattedMusicCacheSize() -> String {
        formatBytes(musicCacheSize)
    }

    func formattedLyricsCacheSize() -> String {
        formatBytes(lyricsCacheSize)
    }

    // MARK: - Maintenance cores (run on maintenanceQueue, never the main actor)

    private nonisolated func publishSizes(
        _ sizes: (image: UInt64?, music: UInt64?, lyrics: UInt64?)
    ) {
        if let image = sizes.image, let music = sizes.music, let lyrics = sizes.lyrics {
            DebugLogger.log(
                "Cache sizes — images: \(formatBytes(image)), music: \(formatBytes(music)), lyrics: \(formatBytes(lyrics))",
                category: .cache
            )
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let image = sizes.image { imageCacheSize = image }
            if let music = sizes.music { musicCacheSize = music }
            if let lyrics = sizes.lyrics { lyricsCacheSize = lyrics }
        }
    }

    private nonisolated func computeSizesBlocking(
        directories: (music: URL, lyrics: URL)
    ) -> (image: UInt64?, music: UInt64?, lyrics: UInt64?) {
        (
            image: UInt64(SDImageCache.shared.totalDiskSize()),
            music: directorySize(at: directories.music),
            lyrics: directorySize(at: directories.lyrics)
        )
    }

    private nonisolated func enforceImageCacheLimitsBlocking() -> UInt64 {
        let sdCache = SDImageCache.shared
        let diskSize = UInt64(sdCache.totalDiskSize())

        if diskSize > Self.imageCacheLimit {
            DebugLogger.log(
                "Image cache \(formatBytes(diskSize)) exceeds limit \(formatBytes(Self.imageCacheLimit)), clearing oldest",
                category: .cache
            )
            // SDWebImage prunes its own tree against the maxDiskSize set in
            // ImageCacheConfig; a manual eviction walk here would race that
            // I/O. Wait for the pass so the published size is post-evict.
            let evictionDone = DispatchSemaphore(value: 0)
            sdCache.deleteOldFiles {
                evictionDone.signal()
            }
            evictionDone.wait()
        }

        return UInt64(sdCache.totalDiskSize())
    }

    private nonisolated func enforceMusicCacheLimitsBlocking(
        musicDirectory: URL,
        excluding protectedIDs: Set<String>
    ) -> UInt64 {
        // Runs on every track transition and after every vocal separation;
        // skip the tree walk when nothing was committed since the last run.
        let now = Date()
        if let lastRun = lastMusicEnforcementAt,
           now.timeIntervalSince(lastRun) < Self.enforcementDebounceInterval,
           (Self.lastMusicCommitAt ?? .distantPast) <= lastRun,
           let lastSize = lastMusicCacheSize
        {
            return lastSize
        }
        lastMusicEnforcementAt = now
        let size = evictOldestSongDirectories(
            in: musicDirectory,
            limit: Self.musicCacheLimit,
            excluding: protectedIDs
        )
        lastMusicCacheSize = size
        return size
    }

    private nonisolated func enforceLyricsCacheLimitsBlocking(lyricsDirectory: URL) -> UInt64 {
        // Lyrics saves trigger this per save; the files are tiny, so a light
        // debounce avoids a full enumeration for every cached lyric.
        let now = Date()
        if let lastRun = lastLyricsEnforcementAt,
           now.timeIntervalSince(lastRun) < Self.enforcementDebounceInterval,
           let lastSize = lastLyricsCacheSize
        {
            return lastSize
        }
        lastLyricsEnforcementAt = now
        let size = evictOldestFiles(in: lyricsDirectory, limit: Self.lyricsCacheLimit, label: "lyrics")
        lastLyricsCacheSize = size
        return size
    }

    private nonisolated func pruneExpiredEntriesBlocking(
        directories: (music: URL, lyrics: URL)
    ) -> Int {
        let cutoff = Date().addingTimeInterval(-Self.maxCacheAge)
        DebugLogger.log("Pruning cache entries older than \(cutoff)", category: .cache)

        var prunedCount = 0
        prunedCount += pruneOldSongDirectories(in: directories.music, olderThan: cutoff)
        prunedCount += pruneOldFiles(in: directories.lyrics, olderThan: cutoff)
        SDImageCache.shared.deleteOldFiles(completionBlock: nil)
        return prunedCount
    }

    // MARK: - File helpers

    private nonisolated func directorySize(at url: URL) -> UInt64 {
        measuredDirectorySize(at: url) ?? 0
    }

    private nonisolated func measuredDirectorySize(at url: URL) -> UInt64? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else { return nil }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += UInt64(size)
        }
        return total
    }

    private nonisolated func evictOldestFiles(in directory: URL, limit: UInt64, label: String) -> UInt64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return 0 }

        var currentSize = directorySize(at: directory)
        guard currentSize > limit else { return currentSize }

        DebugLogger.log(
            "\(label) cache \(formatBytes(currentSize)) > limit \(formatBytes(limit)), evicting oldest",
            category: .cache
        )

        let sortedFiles = filesOrderedByDate(in: directory)

        var evicted = 0
        for file in sortedFiles {
            guard currentSize > limit else { break }
            let size = fileSize(at: file)
            do {
                try fm.removeItem(at: file)
                currentSize = currentSize > size ? currentSize - size : 0
                evicted += 1
                DebugLogger.log("Evicted: \(file.lastPathComponent) (\(formatBytes(size)))", category: .cache)
            } catch {
                DebugLogger.log(
                    "Could not evict \(file.lastPathComponent): \(error)",
                    category: .cache
                )
            }
        }

        DebugLogger.log(
            "\(label) cache eviction complete: removed \(evicted) files, new size \(formatBytes(currentSize))",
            category: .cache
        )
        return currentSize
    }

    private nonisolated func evictOldestSongDirectories(
        in directory: URL,
        limit: UInt64,
        excluding protectedIDs: Set<String> = []
    ) -> UInt64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return 0 }

        var currentSize = directorySize(at: directory)
        guard currentSize > limit else { return currentSize }

        DebugLogger.log(
            "music cache \(formatBytes(currentSize)) > limit \(formatBytes(limit)), evicting oldest song folders",
            category: .cache
        )

        for folder in songDirectoriesOrderedByDate(in: directory) {
            guard currentSize > limit else { break }
            if protectedIDs.contains(folder.lastPathComponent) { continue }
            // A streaming download commits into the song folder through a
            // .partial file; never evict a folder mid-commit.
            if containsPartialFiles(folder) { continue }
            let size = directorySize(at: folder)
            do {
                try fm.removeItem(at: folder)
                currentSize = currentSize > size ? currentSize - size : 0
                DebugLogger.log("Evicted song cache: \(folder.lastPathComponent) (\(formatBytes(size)))", category: .cache)
            } catch {
                DebugLogger.log(
                    "Could not evict song cache \(folder.lastPathComponent): \(error)",
                    category: .cache
                )
            }
        }
        if currentSize > limit {
            // The running total was subtracted from a stale pre-pass size and
            // skips protected/partial folders; re-stat what actually remains.
            currentSize = directorySize(at: directory)
        }
        return currentSize
    }

    private nonisolated func containsPartialFiles(_ directory: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        return entries.contains { $0.contains(".partial.") }
    }

    private nonisolated func pruneOldFiles(in directory: URL, olderThan cutoff: Date) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else { return 0 }

        var count = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
                values.isRegularFile == true,
                let modified = values.contentModificationDate,
                modified < cutoff
            else { continue }
            do {
                try fm.removeItem(at: fileURL)
                count += 1
            } catch {}
        }
        return count
    }

    private nonisolated func pruneOldSongDirectories(
        in directory: URL,
        olderThan cutoff: Date,
        excluding protectedIDs: Set<String> = []
    ) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return 0 }
        guard
            let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return 0
        }

        var count = 0
        for folder in entries {
            if protectedIDs.contains(folder.lastPathComponent) { continue }
            guard let values = try? folder.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory == true,
                  let modified = values.contentModificationDate,
                  modified < cutoff
            else {
                continue
            }
            do {
                try fm.removeItem(at: folder)
                count += 1
            } catch {}
        }
        return count
    }

    private nonisolated func filesOrderedByDate(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else { return [] }

        var files: [(url: URL, date: Date)] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
                values.isRegularFile == true,
                let modified = values.contentModificationDate
            else { continue }
            files.append((url: fileURL, date: modified))
        }
        return files.sorted { $0.date < $1.date }.map(\.url)
    }

    private nonisolated func fileSize(at url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return 0 }
        return UInt64(size)
    }

    private nonisolated func songDirectoriesOrderedByDate(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return entries
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                      values.isDirectory == true,
                      let modified = values.contentModificationDate
                else {
                    return nil
                }
                return (url, modified)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private nonisolated func removeAllFiles(in directory: URL) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        else { return }
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
    }

    // Deliberately per-call: ByteCountFormatter is not Sendable and not
    // thread-safe, and this is called from both the maintenance queue and the
    // main actor. Caching one instance would be a data race, and this is a
    // cold path (one maintenance pass, eviction logs, Settings size labels).
    private nonisolated func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
