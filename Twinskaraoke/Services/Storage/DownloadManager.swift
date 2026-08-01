import Combine
import Foundation
import Network
import SwiftUI

// Called from URLSession completion handlers off the main actor; NSLock-guarded.
// A replacement remains the destination protector while it is active and, if
// successful, until every older callback has resolved. This prevents a late
// completion from deleting the replacement's file without retaining tokens
// indefinitely.
nonisolated final class DownloadTaskRegistry: @unchecked Sendable {
    struct Resolution: Equatable, Sendable {
        let isCurrent: Bool
        let hasReplacementOwner: Bool
        let shouldRemoveDestination: Bool
    }

    private struct Entry {
        var currentToken: UUID?
        var pendingTokens: Set<UUID>
        var hasDeferredStaleMove: Bool
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func register(songID: String, token: UUID) {
        lock.lock()
        var entry = entries[songID] ?? Entry(
            currentToken: nil,
            pendingTokens: [],
            hasDeferredStaleMove: false
        )
        entry.currentToken = token
        entry.pendingTokens.insert(token)
        entries[songID] = entry
        lock.unlock()
    }

    @discardableResult
    func invalidate(songID: String) -> Bool {
        lock.lock()
        guard var entry = entries[songID] else {
            lock.unlock()
            return false
        }
        entry.currentToken = nil
        let shouldRemoveDestination = entry.hasDeferredStaleMove
        entry.hasDeferredStaleMove = false
        if entry.pendingTokens.isEmpty {
            entries.removeValue(forKey: songID)
        } else {
            entries[songID] = entry
        }
        lock.unlock()
        return shouldRemoveDestination
    }

    func invalidateAllAfterDestinationCleanup() {
        lock.lock()
        for songID in Array(entries.keys) {
            guard var entry = entries[songID] else { continue }
            entry.currentToken = nil
            entry.hasDeferredStaleMove = false
            if entry.pendingTokens.isEmpty {
                entries.removeValue(forKey: songID)
            } else {
                entries[songID] = entry
            }
        }
        lock.unlock()
    }

    func resolveCompletion(songID: String, token: UUID, moved: Bool) -> Resolution {
        lock.lock()
        defer { lock.unlock() }

        guard var entry = entries[songID] else {
            return Resolution(
                isCurrent: false,
                hasReplacementOwner: false,
                shouldRemoveDestination: moved
            )
        }

        let isCurrent = entry.currentToken == token
        var shouldRemoveDestination = false
        if isCurrent {
            if moved {
                entry.hasDeferredStaleMove = false
            } else {
                // A failed replacement no longer protects a file written by an
                // older task. If that task already completed, perform its
                // deferred destination cleanup now.
                entry.currentToken = nil
                shouldRemoveDestination = entry.hasDeferredStaleMove
                entry.hasDeferredStaleMove = false
            }
        } else if moved {
            if entry.currentToken != nil {
                entry.hasDeferredStaleMove = true
            } else {
                shouldRemoveDestination = true
            }
        }
        entry.pendingTokens.remove(token)
        let hasReplacementOwner = entry.currentToken != nil && entry.currentToken != token

        if entry.pendingTokens.isEmpty {
            entries.removeValue(forKey: songID)
        } else {
            entries[songID] = entry
        }
        return Resolution(
            isCurrent: isCurrent,
            hasReplacementOwner: hasReplacementOwner,
            shouldRemoveDestination: shouldRemoveDestination
        )
    }

    func performIfCurrent<T>(songID: String, token: UUID, _ body: () throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard entries[songID]?.currentToken == token else { return nil }
        return try body()
    }
}

nonisolated struct SongDownloadStatus: Equatable, Sendable {
    let isDownloaded: Bool
    let isDownloading: Bool

    static func make(
        downloadedIDs: Set<String>,
        inProgress: Set<String>,
        songID: String
    ) -> SongDownloadStatus {
        SongDownloadStatus(
            isDownloaded: downloadedIDs.contains(songID),
            isDownloading: !downloadedIDs.contains(songID) && inProgress.contains(songID)
        )
    }
}

nonisolated struct SongCollectionDownloadStatus: Equatable, Sendable {
    let pendingSongs: [Song]
    let inFlightCount: Int

    static func make(
        downloadedIDs: Set<String>,
        inProgress: Set<String>,
        songs: [Song]
    ) -> SongCollectionDownloadStatus {
        SongCollectionDownloadStatus(
            pendingSongs: songs.filter { song in
                !downloadedIDs.contains(song.id) && !inProgress.contains(song.id)
            },
            inFlightCount: songs.filter { inProgress.contains($0.id) }.count
        )
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    private struct SongFiles {
        let directory: URL
        let audio: URL
        let source: URL
        let metadata: URL
    }

    private struct ValidDownloadCacheEntry {
        let source: String?
        let expectedDuration: TimeInterval?
        let modifiedAt: Date?
    }

    private struct StartupScanResult {
        let validIDs: Set<String>
        let validEntries: [String: ValidDownloadCacheEntry]
        let repairs: [String: Song]
        let junkSongIDs: [String]
    }

    static let shared = DownloadManager()
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var inProgress: Set<String> = []
    @Published private(set) var progress: [String: Double] = [:]
    private let cacheDir: URL
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var queuedDownloads: [String: Song] = [:]
    private var queuedDownloadOrder: [String] = []
    private var isLoggingDownloadQueue = false
    private var completedInCurrentQueue = 0
    private var failedInCurrentQueue = 0
    private var pendingWiFiRepairs: [String: Song] = [:]
    private var validDownloadCache: [String: ValidDownloadCacheEntry] = [:]
    private var isWiFiAvailable = false
    private let taskRegistry = DownloadTaskRegistry()
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "DownloadManager.NetworkMonitor")
    private let maxConcurrentDownloads = 6

    private init() {
        cacheDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        startNetworkMonitoring()
        // The startup scan opens every downloaded audio file to validate it;
        // that per-file decode work must stay off the main thread at launch.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let scan = scanExistingDownloadsBlocking()
            await MainActor.run {
                self.applyStartupScan(scan)
            }
        }
    }

    deinit {
        networkMonitor.cancel()
    }

    private nonisolated func files(for songID: String) -> SongFiles {
        let directory = cacheDir.appendingPathComponent(songID, isDirectory: true)
        return SongFiles(
            directory: directory,
            audio: directory.appendingPathComponent("main.mp3"),
            source: directory.appendingPathComponent("main.source"),
            metadata: directory.appendingPathComponent("metadata.json")
        )
    }

    private nonisolated func ensureSongDirectory(for songID: String) {
        try? FileManager.default.createDirectory(
            at: files(for: songID).directory,
            withIntermediateDirectories: true
        )
    }

    nonisolated func localURL(for songID: String) -> URL {
        files(for: songID).audio
    }

    private nonisolated func sourceURL(for songID: String) -> URL {
        files(for: songID).source
    }

    nonisolated static func durationAppearsComplete(
        actualDuration: TimeInterval,
        expectedDuration: TimeInterval?
    ) -> Bool {
        guard actualDuration.isFinite, actualDuration > 1.0 else { return false }
        guard let expectedDuration, expectedDuration.isFinite, expectedDuration > 1.0 else {
            return true
        }

        // Catalog durations are rounded and can differ slightly from decoded media duration.
        // A longer file is complete; only a materially shorter file indicates truncation.
        let tolerance = max(5.0, min(15.0, expectedDuration * 0.03))
        return actualDuration + tolerance >= expectedDuration
    }

    nonisolated static func downloadedAudioURL(in directory: URL, sourceURL: URL) -> URL {
        directory.appendingPathComponent("main.\(audioExtension(for: sourceURL))")
    }

    nonisolated static func commitDownloadedAudioFile(
        at stagedURL: URL,
        to finalURL: URL,
        in directory: URL
    ) throws {
        guard FileManager.default.fileExists(atPath: stagedURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: stagedURL, to: finalURL)
        removeDownloadedAudioVariants(in: directory, preserving: finalURL)
    }

    nonisolated static func removePromotionStagingFiles(in directory: URL, createdBefore cutoff: Date) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in entries {
            guard url.lastPathComponent.contains(".promoting-"),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                      .contentModificationDate,
                  modifiedAt < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated static func resumeData(from error: Error) -> Data? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain,
              nsError.code == NSURLErrorNetworkConnectionLost
        else { return nil }
        return nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    }

    nonisolated static func isPendingDeletionDirectoryName(_ name: String) -> Bool {
        name.hasPrefix("Downloads.pending-delete-")
    }

    private nonisolated static func isValidDownloadedAudio(
        at url: URL,
        expectedDuration: TimeInterval? = nil
    ) -> Bool {
        guard AudioCacheStore.isPlayableAudioFile(at: url) else { return false }
        let actualDuration = AudioCacheStore.audioDuration(at: url)
        return durationAppearsComplete(
            actualDuration: actualDuration,
            expectedDuration: expectedDuration
        )
    }

    private nonisolated static func audioExtension(for sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.lowercased()
        return ext.isEmpty ? "mp3" : ext
    }

    private nonisolated static func removeDownloadedAudioVariants(
        in directory: URL,
        preserving finalURL: URL
    ) {
        for ext in ["mp3", "m4a", "aac", "wav", "caf", "aif", "aiff"] {
            let url = directory.appendingPathComponent("main.\(ext)")
            if url != finalURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private nonisolated static func downloadedByteCount(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private nonisolated static func modificationDate(at url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    func isDownloaded(_ songID: String) -> Bool {
        downloadedIDs.contains(songID)
    }

    func isDownloading(_ songID: String) -> Bool {
        inProgress.contains(songID)
    }

    func status(for songID: String) -> SongDownloadStatus {
        SongDownloadStatus.make(
            downloadedIDs: downloadedIDs,
            inProgress: inProgress,
            songID: songID
        )
    }

    func status(for songs: [Song]) -> SongCollectionDownloadStatus {
        SongCollectionDownloadStatus.make(
            downloadedIDs: downloadedIDs,
            inProgress: inProgress,
            songs: songs
        )
    }

    func statusPublisher(for songID: String) -> AnyPublisher<SongDownloadStatus, Never> {
        Publishers.CombineLatest($downloadedIDs, $inProgress)
            .map { downloadedIDs, inProgress in
                SongDownloadStatus.make(
                    downloadedIDs: downloadedIDs,
                    inProgress: inProgress,
                    songID: songID
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var hasActiveQueue: Bool {
        !tasks.isEmpty || !queuedDownloadOrder.isEmpty
    }

    func download(song: Song) {
        guard song.audioURL != nil else { return }
        if isDownloaded(song.id), playableURL(for: song) != nil { return }
        guard !isDownloading(song.id) else { return }
        if !isLoggingDownloadQueue {
            isLoggingDownloadQueue = true
            completedInCurrentQueue = 0
            failedInCurrentQueue = 0
            DebugLogger.log("Download queue started", category: .network)
        }
        pendingWiFiRepairs.removeValue(forKey: song.id)
        inProgress.insert(song.id)
        progress[song.id] = 0
        queuedDownloads[song.id] = song
        queuedDownloadOrder.append(song.id)
        startQueuedDownloadsIfPossible()
    }

    func download(songs: [Song]) {
        for song in songs {
            download(song: song)
        }
    }

    private func startQueuedDownloadsIfPossible() {
        while tasks.count < maxConcurrentDownloads, !queuedDownloadOrder.isEmpty {
            let songID = queuedDownloadOrder.removeFirst()
            guard let song = queuedDownloads.removeValue(forKey: songID) else { continue }
            guard inProgress.contains(songID), !downloadedIDs.contains(songID) else {
                inProgress.remove(songID)
                progress.removeValue(forKey: songID)
                continue
            }
            startDownloadTask(song: song)
        }
    }

    private func startDownloadTask(song: Song) {
        guard let remote = song.audioURL else {
            finishDownload(songID: song.id, song: song, moved: false)
            return
        }
        let songID = song.id
        let songFiles = files(for: songID)
        let token = UUID()
        let taskRegistry = taskRegistry
        taskRegistry.register(songID: songID, token: token)
        ensureSongDirectory(for: songID)
        let task = URLSession.shared.downloadTask(with: remote) { [weak self] tempURL, response, error in
            var moved = false
            let expectedBytes = response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown
            let downloadedBytes = tempURL.map { Self.downloadedByteCount(at: $0) } ?? 0
            let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
            let hasCompleteByteCount = expectedBytes <= 0 || Int64(downloadedBytes) >= expectedBytes
            if let tempURL, error == nil, AudioCacheStore.acceptsAudioResponse(response),
               hasCompleteByteCount,
               Self.isValidDownloadedAudio(at: tempURL, expectedDuration: expectedDuration)
            {
                do {
                    moved = try taskRegistry.performIfCurrent(songID: songID, token: token) {
                        try FileManager.default.createDirectory(
                            at: songFiles.directory,
                            withIntermediateDirectories: true
                        )
                        try? FileManager.default.removeItem(at: songFiles.audio)
                        try FileManager.default.moveItem(at: tempURL, to: songFiles.audio)
                        try? FileManager.default.removeItem(at: songFiles.source)
                        FileManager.default.createFile(
                            atPath: songFiles.source.path,
                            contents: remote.absoluteString.data(using: .utf8)
                        )
                        return true
                    } ?? false
                    if !moved {
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                } catch {
                    DebugLogger.log("Download move failed for \(songID): \(error)", category: .network)
                }
            } else {
                if let tempURL {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                if error == nil {
                    DebugLogger.log(
                        "Download rejected invalid audio for \(songID): bytes=\(downloadedBytes), expectedBytes=\(expectedBytes)",
                        category: .network
                    )
                }
            }
            Task { @MainActor [weak self, moved, song, songID, token] in
                self?.finishDownload(songID: songID, song: song, moved: moved, token: token)
            }
        }
        tasks[song.id] = task
        task.resume()
    }

    private func finishDownload(songID: String, song: Song, moved: Bool, token: UUID? = nil) {
        if let token {
            let resolution = taskRegistry.resolveCompletion(
                songID: songID,
                token: token,
                moved: moved
            )
            if resolution.shouldRemoveDestination {
                let songFiles = files(for: songID)
                try? FileManager.default.removeItem(at: songFiles.audio)
                try? FileManager.default.removeItem(at: songFiles.source)
            }
            guard resolution.isCurrent else {
                // A replacement uses the same destination. Its ownership token
                // survives successful completion until older callbacks settle.
                startQueuedDownloadsIfPossible()
                logDownloadQueueCompletionIfNeeded()
                return
            }
        }
        tasks.removeValue(forKey: songID)
        let wasInProgress = inProgress.remove(songID) != nil
        progress.removeValue(forKey: songID)
        guard wasInProgress else {
            startQueuedDownloadsIfPossible()
            logDownloadQueueCompletionIfNeeded()
            return
        }
        if moved {
            writeMetadata(for: song)
            downloadedIDs.insert(songID)
            validDownloadCache[songID] = ValidDownloadCacheEntry(
                source: song.audioURL?.absoluteString,
                expectedDuration: song.duration > 0 ? TimeInterval(song.duration) : nil,
                modifiedAt: Self.modificationDate(at: files(for: songID).audio)
            )
            completedInCurrentQueue += 1
        } else {
            failedInCurrentQueue += 1
            DebugLogger.log("Download failed: \(songID)", category: .network)
        }
        startQueuedDownloadsIfPossible()
        logDownloadQueueCompletionIfNeeded()
    }

    func cancel(songID: String) {
        let shouldRemoveDestination = taskRegistry.invalidate(songID: songID)
        if shouldRemoveDestination {
            let songFiles = files(for: songID)
            try? FileManager.default.removeItem(at: songFiles.audio)
            try? FileManager.default.removeItem(at: songFiles.source)
        }
        tasks[songID]?.cancel()
        tasks.removeValue(forKey: songID)
        queuedDownloads.removeValue(forKey: songID)
        queuedDownloadOrder.removeAll { $0 == songID }
        inProgress.remove(songID)
        progress.removeValue(forKey: songID)
        startQueuedDownloadsIfPossible()
        logDownloadQueueCompletionIfNeeded()
    }

    func remove(songID: String) {
        cancel(songID: songID)
        pendingWiFiRepairs.removeValue(forKey: songID)
        validDownloadCache.removeValue(forKey: songID)
        let songFiles = files(for: songID)
        try? FileManager.default.removeItem(at: songFiles.directory)
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("\(songID).mp3"))
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("\(songID).source"))
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("\(songID).json"))
        downloadedIDs.remove(songID)
        DebugLogger.log("Download removed: \(songID)", category: .network)
    }

    func remove(songIDs: [String]) {
        for songID in songIDs {
            remove(songID: songID)
        }
    }

    func removeAll() {
        for task in tasks.values {
            task.cancel()
        }
        taskRegistry.invalidateAllAfterDestinationCleanup()
        tasks.removeAll()
        queuedDownloads.removeAll()
        queuedDownloadOrder.removeAll()
        isLoggingDownloadQueue = false
        completedInCurrentQueue = 0
        failedInCurrentQueue = 0
        inProgress.removeAll()
        progress.removeAll()
        pendingWiFiRepairs.removeAll()
        validDownloadCache.removeAll()

        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for f in files {
                try? fm.removeItem(at: f)
            }
        }
        downloadedIDs = []
        DebugLogger.log("All downloads removed", category: .network)
    }

    private func logDownloadQueueCompletionIfNeeded() {
        guard isLoggingDownloadQueue, tasks.isEmpty, queuedDownloadOrder.isEmpty else { return }
        DebugLogger.log(
            "Download queue complete: completed=\(completedInCurrentQueue), failed=\(failedInCurrentQueue)",
            category: .network
        )
        isLoggingDownloadQueue = false
        completedInCurrentQueue = 0
        failedInCurrentQueue = 0
    }

    /// Read-only for song directories: the scan runs concurrently with live
    /// downloads, so destructive cleanup is deferred to `applyStartupScan`,
    /// which runs on the main actor and can defer to live download state.
    private nonisolated func scanExistingDownloadsBlocking() -> StartupScanResult {
        migrateLegacyDownloadsIfNeeded()
        let fm = FileManager.default
        var ids = Set<String>()
        var validEntries: [String: ValidDownloadCacheEntry] = [:]
        var repairs: [String: Song] = [:]
        var junkSongIDs: [String] = []
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        else {
            return StartupScanResult(
                validIDs: ids, validEntries: validEntries, repairs: repairs, junkSongIDs: junkSongIDs
            )
        }
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory else {
                // Loose files at the root are pre-migration leftovers; no
                // live download writes them, so removal here cannot race.
                try? fm.removeItem(at: entry)
                continue
            }
            let songID = entry.lastPathComponent
            if hasValidDownload(for: songID) {
                ids.insert(songID)
                let metadata = readMetadata(for: songID)
                let metadataDuration = metadata?.duration ?? 0
                validEntries[songID] = ValidDownloadCacheEntry(
                    source: readSourceURL(for: songID),
                    expectedDuration: metadataDuration > 0 ? TimeInterval(metadataDuration) : nil,
                    modifiedAt: Self.modificationDate(at: files(for: songID).audio)
                )
            } else {
                let repairSong = readMetadata(for: songID)
                if let repairSong, repairSong.audioURL != nil {
                    repairs[songID] = repairSong
                } else {
                    junkSongIDs.append(songID)
                }
            }
        }
        return StartupScanResult(
            validIDs: ids, validEntries: validEntries, repairs: repairs, junkSongIDs: junkSongIDs
        )
    }

    private func applyStartupScan(_ scan: StartupScanResult) {
        // Downloads may have started, finished, or been removed while the
        // scan ran; merge instead of overwriting, and let live state win.
        let fm = FileManager.default
        let stillExistingIDs = scan.validIDs.filter { songID in
            fm.fileExists(atPath: files(for: songID).audio.path)
        }
        downloadedIDs.formUnion(stillExistingIDs)
        for (songID, entry) in scan.validEntries
            where stillExistingIDs.contains(songID) && validDownloadCache[songID] == nil
        {
            validDownloadCache[songID] = entry
        }
        var repairCount = 0
        for (songID, song) in scan.repairs {
            guard !downloadedIDs.contains(songID), !inProgress.contains(songID) else { continue }
            // A missing metadata file means the song was removed during the
            // scan; don't delete anything or resurrect it as a repair.
            let songFiles = files(for: songID)
            guard fm.fileExists(atPath: songFiles.metadata.path) else { continue }
            try? fm.removeItem(at: songFiles.audio)
            try? fm.removeItem(at: songFiles.source)
            pendingWiFiRepairs[songID] = song
            repairCount += 1
        }
        for songID in scan.junkSongIDs {
            guard !downloadedIDs.contains(songID), !inProgress.contains(songID) else { continue }
            try? fm.removeItem(at: files(for: songID).directory)
        }
        DebugLogger.log(
            "DownloadManager scan complete — \(downloadedIDs.count) existing downloads, \(repairCount) pending repair(s)",
            category: .network
        )
        startPendingWiFiRepairsIfPossible()
    }

    func playableURL(for song: Song) -> URL? {
        migrateLegacyDownloadIfNeeded(for: song.id)
        let songFiles = files(for: song.id)
        guard FileManager.default.fileExists(atPath: songFiles.audio.path) else {
            downloadedIDs.remove(song.id)
            validDownloadCache.removeValue(forKey: song.id)
            return nil
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        let expectedSource = song.audioURL?.absoluteString
        let cachedSource = readSourceURL(for: song.id)
        if let cachedSource, let expectedSource, cachedSource != expectedSource {
            DebugLogger.log(
                "Discarding downloaded audio for \(song.id) due to source mismatch",
                category: .cache
            )
            discardBrokenDownloadAndScheduleRepair(for: song, reason: "source URL changed")
            return nil
        }
        let resolvedSource = cachedSource ?? expectedSource
        if hasCachedValidation(
            for: song.id,
            audioURL: songFiles.audio,
            source: resolvedSource,
            expectedDuration: expectedDuration
        ) {
            return songFiles.audio
        }
        guard let cachedSource else {
            if let expected = song.audioURL {
                writeSourceURL(expected, for: song.id)
                writeMetadata(for: song)
                downloadedIDs.insert(song.id)
                DebugLogger.log(
                    "Repaired missing download source metadata for \(song.id)",
                    category: .cache
                )
            }
            guard Self.isValidDownloadedAudio(at: songFiles.audio, expectedDuration: expectedDuration) else {
                DebugLogger.log("Discarding invalid downloaded audio for \(song.id)", category: .cache)
                discardBrokenDownloadAndScheduleRepair(for: song, reason: "file validation failed")
                return nil
            }
            cacheValidDownload(
                songID: song.id,
                audioURL: songFiles.audio,
                source: expectedSource,
                expectedDuration: expectedDuration
            )
            return songFiles.audio
        }
        guard Self.isValidDownloadedAudio(at: songFiles.audio, expectedDuration: expectedDuration) else {
            DebugLogger.log("Discarding invalid downloaded audio for \(song.id)", category: .cache)
            discardBrokenDownloadAndScheduleRepair(for: song, reason: "file validation failed")
            return nil
        }
        cacheValidDownload(
            songID: song.id,
            audioURL: songFiles.audio,
            source: cachedSource,
            expectedDuration: expectedDuration
        )
        return songFiles.audio
    }

    private func hasCachedValidation(
        for songID: String,
        audioURL: URL,
        source: String?,
        expectedDuration: TimeInterval?
    ) -> Bool {
        guard let cached = validDownloadCache[songID] else { return false }
        return cached.source == source
            && cached.expectedDuration == expectedDuration
            && cached.modifiedAt == Self.modificationDate(at: audioURL)
    }

    private func cacheValidDownload(
        songID: String,
        audioURL: URL,
        source: String?,
        expectedDuration: TimeInterval?
    ) {
        validDownloadCache[songID] = ValidDownloadCacheEntry(
            source: source,
            expectedDuration: expectedDuration,
            modifiedAt: Self.modificationDate(at: audioURL)
        )
    }

    /// Returns true only when the on-disk download is conclusively invalid and was removed.
    /// Playback callbacks alone are not evidence that a download is corrupt.
    @discardableResult
    func repairIfDownloadedFileIsBroken(for song: Song) -> Bool {
        guard isDownloaded(song.id) else { return false }
        let songFiles = files(for: song.id)
        guard FileManager.default.fileExists(atPath: songFiles.audio.path) else {
            discardBrokenDownloadAndScheduleRepair(for: song, reason: "audio file is missing")
            return true
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        guard !Self.isValidDownloadedAudio(
            at: songFiles.audio,
            expectedDuration: expectedDuration
        ) else {
            return false
        }
        discardBrokenDownloadAndScheduleRepair(for: song, reason: "file validation failed")
        return true
    }

    func downloadedSongs(knownSongs: [Song] = []) -> [Song] {
        var songs: [Song] = []
        var seen = Set<String>()

        for song in knownSongs where downloadedIDs.contains(song.id) {
            guard !seen.contains(song.id) else { continue }
            guard playableURL(for: song) != nil else { continue }
            songs.append(song)
            seen.insert(song.id)
        }

        for songID in downloadedIDs.sorted() where !seen.contains(songID) {
            guard let song = readMetadata(for: songID), playableURL(for: song) != nil else { continue }
            songs.append(song)
            seen.insert(songID)
        }

        return songs.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private nonisolated func hasValidDownload(for songID: String) -> Bool {
        let songFiles = files(for: songID)
        guard FileManager.default.fileExists(atPath: songFiles.audio.path) else { return false }
        let metadata = readMetadata(for: songID)
        let metadataDuration = metadata?.duration ?? 0
        let expectedDuration = metadataDuration > 0 ? TimeInterval(metadataDuration) : nil
        guard Self.isValidDownloadedAudio(
            at: songFiles.audio,
            expectedDuration: expectedDuration
        ) else {
            return false
        }

        guard let cachedSource = readSourceURL(for: songID) else {
            if let remoteURL = metadata?.audioURL {
                writeSourceURL(remoteURL, for: songID)
            }
            return true
        }
        guard let expectedSource = metadata?.audioURL?.absoluteString else { return true }
        return cachedSource == expectedSource
    }

    private nonisolated func readSourceURL(for songID: String) -> String? {
        guard let data = try? Data(contentsOf: sourceURL(for: songID)),
              let rawValue = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private nonisolated func writeSourceURL(_ remoteURL: URL, for songID: String) {
        let source = sourceURL(for: songID)
        ensureSongDirectory(for: songID)
        try? FileManager.default.removeItem(at: source)
        FileManager.default.createFile(
            atPath: source.path,
            contents: remoteURL.absoluteString.data(using: .utf8)
        )
    }

    private func discardBrokenDownloadAndScheduleRepair(for song: Song, reason: String) {
        let repairSong: Song? = if song.audioURL != nil {
            song
        } else if let persistedSong = readMetadata(for: song.id), persistedSong.audioURL != nil {
            persistedSong
        } else {
            nil
        }
        DebugLogger.log(
            "Removing confirmed broken download for \(song.id): \(reason)",
            category: .cache
        )
        validDownloadCache.removeValue(forKey: song.id)
        removeBrokenAudioFiles(for: song)
        guard let repairSong else { return }
        pendingWiFiRepairs[song.id] = repairSong
        startPendingWiFiRepairsIfPossible()
    }

    private func removeBrokenAudioFiles(for song: Song) {
        cancel(songID: song.id)
        let songFiles = files(for: song.id)
        validDownloadCache.removeValue(forKey: song.id)
        try? FileManager.default.removeItem(at: songFiles.audio)
        try? FileManager.default.removeItem(at: songFiles.source)
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("\(song.id).mp3"))
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("\(song.id).source"))
        downloadedIDs.remove(song.id)
        if song.audioURL != nil {
            writeMetadata(for: song)
        }
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let hasWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in
                guard let self else { return }
                isWiFiAvailable = hasWiFi
                startPendingWiFiRepairsIfPossible()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func startPendingWiFiRepairsIfPossible() {
        guard isWiFiAvailable, !pendingWiFiRepairs.isEmpty else { return }
        let repairs = Array(pendingWiFiRepairs.values)
        pendingWiFiRepairs.removeAll()
        DebugLogger.log(
            "Wi-Fi available — repairing \(repairs.count) broken download(s)",
            category: .network
        )
        for song in repairs {
            download(song: song)
        }
    }

    private nonisolated func writeMetadata(for song: Song) {
        let songFiles = files(for: song.id)
        ensureSongDirectory(for: song.id)
        guard let data = try? JSONEncoder().encode(song) else { return }
        try? data.write(to: songFiles.metadata, options: [.atomic])
    }

    private nonisolated func readMetadata(for songID: String) -> Song? {
        let metadataURL = files(for: songID).metadata
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(Song.self, from: data)
    }

    private nonisolated func migrateLegacyDownloadsIfNeeded() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        else { return }

        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard !isDirectory else { continue }
            guard entry.pathExtension.lowercased() == "mp3" else {
                if entry.pathExtension.lowercased() == "source" {
                    continue
                }
                try? fm.removeItem(at: entry)
                continue
            }

            let songID = entry.deletingPathExtension().lastPathComponent
            migrateLegacyDownloadIfNeeded(for: songID)
        }

        if let entries = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries where entry.pathExtension.lowercased() == "source" {
                try? fm.removeItem(at: entry)
            }
        }
    }

    private nonisolated func migrateLegacyDownloadIfNeeded(for songID: String) {
        let fm = FileManager.default
        let legacyAudio = cacheDir.appendingPathComponent("\(songID).mp3")
        let legacySource = cacheDir.appendingPathComponent("\(songID).source")
        guard fm.fileExists(atPath: legacyAudio.path) || fm.fileExists(atPath: legacySource.path) else {
            return
        }

        if hasValidDownload(for: songID) {
            try? fm.removeItem(at: legacyAudio)
            try? fm.removeItem(at: legacySource)
            try? fm.removeItem(at: cacheDir.appendingPathComponent("\(songID).json"))
            return
        }

        guard let sourceValue = readLegacySourceURL(for: songID),
              fm.fileExists(atPath: legacyAudio.path),
              AudioCacheStore.isPlayableAudioFile(at: legacyAudio)
        else {
            try? fm.removeItem(at: legacyAudio)
            try? fm.removeItem(at: legacySource)
            return
        }

        let songFiles = files(for: songID)
        ensureSongDirectory(for: songID)
        try? fm.removeItem(at: songFiles.audio)
        try? fm.removeItem(at: songFiles.source)

        do {
            try fm.moveItem(at: legacyAudio, to: songFiles.audio)
            fm.createFile(atPath: songFiles.source.path, contents: sourceValue.data(using: .utf8))
            try? fm.removeItem(at: legacySource)
            DebugLogger.log("Migrated legacy download into UUID folder for \(songID)", category: .cache)
        } catch {
            try? fm.removeItem(at: songFiles.audio)
            try? fm.removeItem(at: songFiles.source)
        }
    }

    private nonisolated func readLegacySourceURL(for songID: String) -> String? {
        let legacySource = cacheDir.appendingPathComponent("\(songID).source")
        guard let data = try? Data(contentsOf: legacySource),
              let rawValue = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
