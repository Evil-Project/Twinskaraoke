import Foundation
import Network
import SwiftUI
import Observation

// Called from URLSession completion handlers off the main actor; NSLock-guarded.
private nonisolated final class DownloadTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var activeTokens: [String: UUID] = [:]

    func register(songID: String, token: UUID) {
        lock.lock()
        activeTokens[songID] = token
        lock.unlock()
    }

    func cancel(songID: String) {
        lock.lock()
        activeTokens.removeValue(forKey: songID)
        lock.unlock()
    }

    func suspendAll() -> [String: UUID] {
        lock.lock()
        defer { lock.unlock() }
        let tokens = activeTokens
        activeTokens.removeAll()
        return tokens
    }

    func restore(_ tokens: [String: UUID]) {
        lock.lock()
        for (songID, token) in tokens where activeTokens[songID] == nil {
            activeTokens[songID] = token
        }
        lock.unlock()
    }

    func performIfActive<T>(songID: String, token: UUID, _ body: () throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard activeTokens[songID] == token else { return nil }
        return try body()
    }
}

/// Owns temporary promotion files until the main actor accepts their request.
nonisolated struct DownloadCachePromotion: Sendable {
    let stagedAudio: URL
    let stagedSource: URL
    let audio: URL
    let source: URL
    let directory: URL

    /// Stale work discards only its own staging files, preserving any retry.
    func commit(ifCurrent isCurrent: Bool) throws -> Bool {
        let fm = FileManager.default
        defer {
            try? fm.removeItem(at: stagedAudio)
            try? fm.removeItem(at: stagedSource)
        }
        guard isCurrent else { return false }
        try DownloadManager.commitDownloadedAudioFile(at: stagedAudio, to: audio, in: directory)
        do {
            if fm.fileExists(atPath: source.path) {
                _ = try fm.replaceItemAt(source, withItemAt: stagedSource)
            } else {
                try fm.moveItem(at: stagedSource, to: source)
            }
        } catch {
            try? fm.removeItem(at: audio)
            throw error
        }
        return true
    }
}

struct SongDownloadStatus: Equatable, Sendable {
    let isDownloaded: Bool
    let isDownloading: Bool

    static func make(
        downloadedIDs: Set<String>,
        inProgress: Set<String>,
        songID: String
    ) -> SongDownloadStatus {
        SongDownloadStatus(
            isDownloaded: downloadedIDs.contains(songID),
            isDownloading: inProgress.contains(songID)
        )
    }
}

struct SongCollectionDownloadStatus: Equatable, Sendable {
    let pendingSongs: [Song]
    let inFlightCount: Int

    static func make(
        downloadedIDs: Set<String>,
        inProgress: Set<String>,
        songs: [Song]
    ) -> SongCollectionDownloadStatus {
        var pendingSongs: [Song] = []
        var inFlightCount = 0

        for song in songs {
            if inProgress.contains(song.id) {
                inFlightCount += 1
            } else if !downloadedIDs.contains(song.id) {
                pendingSongs.append(song)
            }
        }

        return SongCollectionDownloadStatus(
            pendingSongs: pendingSongs,
            inFlightCount: inFlightCount
        )
    }
}

@MainActor
@Observable
final class DownloadManager {
    private struct PublishedState: Equatable {
        var downloadedIDs = Set<String>()
        var inProgress = Set<String>()
    }

    private struct SongFiles {
        let directory: URL
        let audio: URL
        let source: URL
        let metadata: URL
    }

    nonisolated struct ValidDownloadCacheEntry: Codable, Sendable {
        let source: String?
        let expectedDuration: TimeInterval?
        let modifiedAt: Date?
        var byteCount: Int?
    }

    enum RestorationState: Equatable { case notStarted, restoring, ready, failed }
    private(set) var restorationState: RestorationState = .notStarted
    private var restorationGeneration = 0
    private var removedDuringRestoration = Set<String>()
    private var changedDuringRestoration = Set<String>()
    private var restorationStartingIDs = Set<String>()

    struct StartupScanResult {
        let hadFailures: Bool
        let validIDs: Set<String>
        let metadata: [String: Song]
    }

    static let shared = DownloadManager()
    private var publishedState = PublishedState()
    var downloadedIDs: Set<String> { publishedState.downloadedIDs }
    var inProgress: Set<String> { publishedState.inProgress }
    private let cacheDir: URL
    private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var cachePromotionTasks: [String: Task<Void, Never>] = [:]
    // Song IDs that already used their one resume-data retry for the current
    // download attempt; a second interruption fails normally.
    private var resumeRetriedSongIDs: Set<String> = []
    private var queuedDownloads: [String: Song] = [:]
    private var queuedDownloadOrder: [String] = []
    private var isLoggingDownloadQueue = false
    private var completedInCurrentQueue = 0
    private var failedInCurrentQueue = 0
    private var cancelledInCurrentQueue = 0
    private var pendingWiFiRepairs: [String: Song] = [:]
    private var validationBatchGeneration = 0
    private var cancellationGenerations: [String: Int] = [:]
    private var validDownloadCache: [String: ValidDownloadCacheEntry] = [:]
    private var downloadedMetadata: [String: Song] = [:]
    private var isWiFiAvailable = false
    private let taskRegistry = DownloadTaskRegistry()
    private let downloadSession: URLSession
    private let backgroundTransport: BackgroundDownloadTransport
    private var pendingDownloads: [String: PendingDownload] = [:]
    private var restoredPendingDownloads = false
    private var pendingJournalLoaded = false
    private var cancelledBeforePendingRestore = Set<String>()
    private var discardPendingOnRestore = false
    private var deferredDownloadRequests: [String: Song] = [:]
    private var pendingRestoration: Task<Void, Never>?
    private var deferredCompletions: [(URLSessionTask, URL?, Error?)] = []
    private var pendingJournalURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending-downloads.json")
    }
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "DownloadManager.NetworkMonitor")
    private nonisolated static let deletionQueue = DispatchQueue(
        label: "DownloadManager.Deletion",
        qos: .utility
    )
    private nonisolated static let pendingDeletionPrefix = "Downloads.pending-delete-"
    private nonisolated static let maxConcurrentDownloads = 3

    private init() {
        let transport = BackgroundDownloadTransport()
        backgroundTransport = transport
        downloadSession = transport.makeSession()
        cacheDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let downloadsParent = cacheDir.deletingLastPathComponent()
        Self.deletionQueue.async {
            Self.removePendingDeletionDirectories(in: downloadsParent)
        }
        startNetworkMonitoring()
        restoreManifest()
        retryRestoration()
    }

    private var manifestURL: URL { cacheDir.appendingPathComponent(".download-manifest.json") }

    private func restoreManifest() {
        do {
            let songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: manifestURL))
            downloadedMetadata = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            publishedState.downloadedIDs = Set(songs.map(\.id))
        } catch {
            DebugLogger.log("Download manifest read: \(error)", category: .cache)
        }
    }

    private func persistManifest() {
        do {
            let songs = downloadedIDs.compactMap { downloadedMetadata[$0] }
            try JSONEncoder().encode(songs).write(to: manifestURL, options: .atomic)
        } catch {
            DebugLogger.log("Download manifest write: \(error)", category: .cache)
        }
    }

    func retryRestoration() {
        restorePendingDownloadsIfNeeded()
        if UIApplication.shared.isProtectedDataAvailable, !deferredCompletions.isEmpty {
            let completions = deferredCompletions
            deferredCompletions.removeAll()
            Task { [weak self] in
                for (task, file, error) in completions {
                    await self?.receiveBackgroundDownload(task: task, file: file, error: error)
                }
            }
        }
        guard restorationState != .restoring else { return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            restorationState = .failed
            DebugLogger.log("Download restoration waiting for protected data", category: .cache)
            return
        }
        if downloadedIDs.isEmpty { restoreManifest() }
        restorationState = .restoring
        removedDuringRestoration.removeAll()
        changedDuringRestoration.removeAll()
        restorationStartingIDs = downloadedIDs
        restorationGeneration += 1
        let generation = restorationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let scan = Self.scanExistingDownloads(in: cacheDir)
            await MainActor.run {
                guard self.restorationGeneration == generation else { return }
                self.applyStartupScan(scan)
            }
        }
    }

    deinit {
        for task in cachePromotionTasks.values {
            task.cancel()
        }
        networkMonitor.cancel()
    }

    private nonisolated func downloadDirectory(for songID: String) -> URL {
        cacheDir.appendingPathComponent(
            SongStorageKey.component(for: songID),
            isDirectory: true
        )
    }

    private nonisolated func sourceFileURL(for songID: String) -> URL {
        downloadDirectory(for: songID).appendingPathComponent("main.source")
    }

    private nonisolated func metadataFileURL(for songID: String) -> URL {
        downloadDirectory(for: songID).appendingPathComponent("metadata.json")
    }

    private nonisolated func files(for songID: String, sourceURL: URL? = nil) -> SongFiles {
        let directory = downloadDirectory(for: songID)
        let source = sourceFileURL(for: songID)
        let persistedSourceURL = readSourceURL(at: source).flatMap(URL.init(string:))
        let resolvedSourceURL = sourceURL ?? persistedSourceURL
        let audio = if let resolvedSourceURL {
            Self.downloadedAudioURL(in: directory, sourceURL: resolvedSourceURL)
        } else {
            Self.downloadedAudioURLs(in: directory).first
                ?? directory.appendingPathComponent("main.mp3")
        }
        return SongFiles(
            directory: directory,
            audio: audio,
            source: source,
            metadata: metadataFileURL(for: songID)
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
        sourceFileURL(for: songID)
    }

    nonisolated static func downloadedAudioURL(in directory: URL, sourceURL: URL) -> URL {
        directory.appendingPathComponent(
            "main.\(AudioCacheStore.mainAudioExtension(for: sourceURL))"
        )
    }

    private nonisolated static func promotionStagingURL(
        in directory: URL,
        sourceURL: URL,
        token: UUID
    ) -> URL {
        directory.appendingPathComponent(
            "main.promoting-\(token.uuidString).\(AudioCacheStore.mainAudioExtension(for: sourceURL))"
        )
    }

    private nonisolated static func downloadedAudioURLs(in directory: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("main.")
                    && !name.contains(".partial.")
                    && !name.contains(".promoting-")
                    && AudioCacheStore.supportedMainAudioExtensions.contains(
                        url.pathExtension.lowercased()
                    )
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private nonisolated static func removeDownloadedAudioFiles(
        in directory: URL,
        excluding preservedURL: URL? = nil
    ) {
        let preservedURL = preservedURL?.standardizedFileURL
        for url in downloadedAudioURLs(in: directory)
            where url.standardizedFileURL != preservedURL
        {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated static func commitDownloadedAudioFile(
        at stagedURL: URL,
        to finalURL: URL,
        in directory: URL
    ) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: finalURL.path) {
            _ = try fm.replaceItemAt(finalURL, withItemAt: stagedURL)
        } else {
            try fm.moveItem(at: stagedURL, to: finalURL)
        }
        removeDownloadedAudioFiles(in: directory, excluding: finalURL)
    }

    nonisolated static func durationAppearsComplete(
        actualDuration: TimeInterval,
        expectedDuration: TimeInterval?
    ) -> Bool {
        AudioCacheStore.durationAppearsComplete(
            actualDuration: actualDuration,
            expectedDuration: expectedDuration
        )
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

    private nonisolated static func downloadedByteCount(at url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }

    private nonisolated static func modificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
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

    private func updatePublishedState(persist: Bool = true, _ update: (inout PublishedState) -> Void) {
        let previous = publishedState
        var next = previous
        update(&next)
        guard next != previous else { return }
        if persist, restorationState == .restoring {
            changedDuringRestoration.formUnion(previous.downloadedIDs.symmetricDifference(next.downloadedIDs))
        }
        publishedState = next
        if persist, previous.downloadedIDs != next.downloadedIDs { persistManifest() }
    }

    var hasActiveQueue: Bool {
        !tasks.isEmpty || !cachePromotionTasks.isEmpty || !queuedDownloadOrder.isEmpty
    }

    func download(song: Song) {
        download(songs: [song])
    }

    func download(songs: [Song]) {
        // Already-downloaded songs are revalidated through playableURL, which
        // on a validation-cache miss opens the file with AVAudioFile. Validate
        // those off the main actor first so 'download all' on a large playlist
        // never decodes audio on the main thread; the warmed cache then makes
        // the enqueue pass skip them for the price of a dictionary lookup.
        let needsValidation = songs.filter {
            $0.audioURL != nil
                && downloadedIDs.contains($0.id)
                && !hasCachedPlayableValidation(for: $0)
        }
        guard needsValidation.isEmpty else {
            let deferredIDs = Set(needsValidation.map(\.id))
            enqueueDownloads(songs.filter { !deferredIDs.contains($0.id) })
            prewarmValidationCache(for: needsValidation)
            return
        }
        enqueueDownloads(songs)
    }

    private func hasCachedPlayableValidation(for song: Song) -> Bool {
        let cachedSource = readSourceURL(for: song.id)
        let storedSourceURL = cachedSource.flatMap(URL.init(string:))
        let songFiles = files(for: song.id, sourceURL: storedSourceURL ?? song.audioURL)
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        return hasCachedValidation(
            for: song.id,
            audioURL: songFiles.audio,
            source: cachedSource ?? song.audioURL?.absoluteString,
            expectedDuration: expectedDuration
        )
    }

    private func prewarmValidationCache(for songs: [Song]) {
        let batchGeneration = validationBatchGeneration
        let generations = Dictionary(songs.map { ($0.id, cancellationGenerations[$0.id, default: 0]) },
            uniquingKeysWith: { _, new in new })
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let entries = self.validateDownloadsForCachePrewarm(songs)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.validationBatchGeneration == batchGeneration else { return }
                for (songID, entry) in entries where self.validDownloadCache[songID] == nil
                    && self.cancellationGenerations[songID, default: 0] == generations[songID] {
                    self.validDownloadCache[songID] = entry
                }
                self.enqueueDownloads(songs.filter {
                    self.cancellationGenerations[$0.id, default: 0] == generations[$0.id]
                })
            }
        }
    }

    /// Mirrors the early-exit checks in playableURL so warmed cache entries
    /// make it return the audio file without AVAudioFile on the main actor.
    /// Missing, stale, or invalid downloads get no entry and can be downloaded
    /// again without repeating the decoder probe on the main actor.
    private nonisolated func validateDownloadsForCachePrewarm(
        _ songs: [Song]
    ) -> [String: ValidDownloadCacheEntry] {
        var entries: [String: ValidDownloadCacheEntry] = [:]
        for song in songs {
            migrateLegacyDownloadIfNeeded(for: song.id)
            migrateMislabeledDownloadedAudioIfNeeded(
                for: song.id,
                expectedSourceURL: song.audioURL
            )
            let cachedSource = readSourceURL(for: song.id)
            let storedSourceURL = cachedSource.flatMap(URL.init(string:))
            let songFiles = files(
                for: song.id,
                sourceURL: storedSourceURL ?? song.audioURL
            )
            guard FileManager.default.fileExists(atPath: songFiles.audio.path) else { continue }
            let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
            let expectedSource = song.audioURL?.absoluteString
            if let cachedSource, let expectedSource, !Self.sameAudioResource(cachedSource, expectedSource) { continue }
            guard Self.isValidDownloadedAudio(
                at: songFiles.audio,
                expectedDuration: expectedDuration
            ) else { continue }
            entries[song.id] = ValidDownloadCacheEntry(
                source: cachedSource ?? expectedSource,
                expectedDuration: expectedDuration,
                modifiedAt: Self.modificationDate(at: songFiles.audio),
                byteCount: Self.downloadedByteCount(at: songFiles.audio)
            )
        }
        return entries
    }

    func handleBackgroundEvents(completion: @escaping @Sendable () -> Void) {
        backgroundTransport.handleEvents(completion: completion)
        restorePendingDownloadsIfNeeded()
    }

    private func persistPendingDownloads() -> Bool {
        guard pendingJournalLoaded else { return false }
        do {
            let url = pendingJournalURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(pendingDownloads.values)).write(to: url, options: .atomic)
            return true
        } catch {
            DebugLogger.log("Pending download journal write failed: \(error)", category: .cache)
            return false
        }
    }

    private func restorePendingDownloadsIfNeeded() {
        guard !restoredPendingDownloads, pendingRestoration == nil,
              UIApplication.shared.isProtectedDataAvailable else { return }
        do {
            let entries = try JSONDecoder().decode([PendingDownload].self, from: Data(contentsOf: pendingJournalURL))
            pendingDownloads = Dictionary(entries.map { ($0.song.id, $0) }, uniquingKeysWith: { _, new in new })
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            pendingDownloads = [:]
        } catch {
            DebugLogger.log("Pending download journal read failed: \(error)", category: .cache)
            return
        }
        pendingJournalLoaded = true
        if discardPendingOnRestore { pendingDownloads.removeAll() }
        for id in cancelledBeforePendingRestore { pendingDownloads.removeValue(forKey: id) }
        if discardPendingOnRestore || !cancelledBeforePendingRestore.isEmpty { _ = persistPendingDownloads() }
        discardPendingOnRestore = false
        cancelledBeforePendingRestore.removeAll()
        pendingRestoration = Task { [weak self] in
            guard let self else { return }
            let existing = await downloadSession.allTasks
            // Read the current journal state after suspension: cancellation may
            // have removed entries while Foundation was enumerating its tasks.
            for task in existing + backgroundTransport.completingTasks() {
                guard let description = task.taskDescription,
                      let entry = pendingDownloads.values.first(where: { $0.token.uuidString == description }),
                      let task = task as? URLSessionDownloadTask else { task.cancel(); continue }
                tasks[entry.song.id] = task
                taskRegistry.register(songID: entry.song.id, token: entry.token)
                task.resume()
            }
            updatePublishedState { $0.inProgress.formUnion(pendingDownloads.keys) }
            do {
                for receipt in try BackgroundDownloadTransport.receipts() {
                    guard let entry = pendingDownloads.values.first(where: { $0.token.uuidString == receipt.token }),
                          let remote = entry.song.audioURL else {
                        BackgroundDownloadTransport.discardReceipt(for: receipt.file)
                        continue
                    }
                    // A live delegate delivery owns this receipt until it has
                    // finished; only recover files left by a previous process.
                    guard tasks[entry.song.id] == nil else { continue }
                    taskRegistry.register(songID: entry.song.id, token: entry.token)
                    await Self.runCompletion(downloadCompletion(song: entry.song, remoteURL: remote, token: entry.token), file: receipt.file, response: receipt.response, error: nil)
                    BackgroundDownloadTransport.discardReceipt(for: receipt.file)
                }
            } catch {
                DebugLogger.log("Download inbox recovery failed: \(error)", category: .cache)
            }
            for entry in pendingDownloads.values where tasks[entry.song.id] == nil {
                queuedDownloads[entry.song.id] = entry.song
                if !queuedDownloadOrder.contains(entry.song.id) { queuedDownloadOrder.append(entry.song.id) }
            }
            updatePublishedState { $0.inProgress.formUnion(pendingDownloads.keys) }
            restoredPendingDownloads = true
            pendingRestoration = nil
            let deferred = Array(deferredDownloadRequests.values)
            deferredDownloadRequests.removeAll()
            if !deferred.isEmpty { enqueueDownloads(deferred) }
            startQueuedDownloadsIfPossible()
        }
    }

    func receiveBackgroundDownload(task: URLSessionTask, file: URL?, error: Error?) async {
        guard UIApplication.shared.isProtectedDataAvailable else {
            deferredCompletions.append((task, file, error))
            return
        }
        restorePendingDownloadsIfNeeded()
        await pendingRestoration?.value
        guard restoredPendingDownloads else {
            // Keep the journal authoritative; retry restoration after unlock.
            // This file has not been committed and must not replace a download.
            deferredCompletions.append((task, file, error))
            return
        }
        guard let description = task.taskDescription,
              let entry = pendingDownloads.values.first(where: { $0.token.uuidString == description }),
              let remoteURL = entry.song.audioURL else {
            if let file { BackgroundDownloadTransport.discardReceipt(for: file) }
            return
        }
        // A completion may arrive during task enumeration. Adopt it only if no
        // replacement task already owns this token's transfer.
        if let current = tasks[entry.song.id], current.taskIdentifier != task.taskIdentifier {
            if let file { BackgroundDownloadTransport.discardReceipt(for: file) }
            return
        }
        taskRegistry.register(songID: entry.song.id, token: entry.token)
        updatePublishedState { $0.inProgress.insert(entry.song.id) }
        await Self.runCompletion(downloadCompletion(song: entry.song, remoteURL: remoteURL, token: entry.token), file: file, response: task.response, error: error)
        if let file { BackgroundDownloadTransport.discardReceipt(for: file) }
    }

    private func enqueueDownloads(_ songs: [Song]) {
        restorePendingDownloadsIfNeeded()
        guard restoredPendingDownloads else {
            for song in songs { deferredDownloadRequests[song.id] = song }
            return
        }
        var nextInProgress = inProgress
        var acceptedAny = false

        for song in songs {
            guard song.audioURL != nil else { continue }
            if downloadedIDs.contains(song.id), immediatelyPlayableURL(for: song) != nil { continue }
            guard !nextInProgress.contains(song.id) else { continue }

            pendingDownloads[song.id] = PendingDownload(song: song, token: UUID())
            guard persistPendingDownloads() else {
                pendingDownloads.removeValue(forKey: song.id)
                continue
            }
            pendingWiFiRepairs.removeValue(forKey: song.id)
            nextInProgress.insert(song.id)
            queuedDownloads[song.id] = song
            queuedDownloadOrder.append(song.id)
            acceptedAny = true
        }

        guard acceptedAny else { return }
        if !isLoggingDownloadQueue {
            isLoggingDownloadQueue = true
            completedInCurrentQueue = 0
            failedInCurrentQueue = 0
            cancelledInCurrentQueue = 0
            DebugLogger.log("Download queue started", category: .network)
        }
        updatePublishedState { $0.inProgress = nextInProgress }
        startQueuedDownloadsIfPossible()
    }

    private func startQueuedDownloadsIfPossible() {
        guard restoredPendingDownloads else { return }
        // Iterate by index and remove the drained prefix in one batch instead
        // of removeFirst() per element, which shifts the whole array each time.
        var drainedCount = 0
        while activeDownloadWorkCount < Self.maxConcurrentDownloads,
              drainedCount < queuedDownloadOrder.count
        {
            let songID = queuedDownloadOrder[drainedCount]
            drainedCount += 1
            guard let song = queuedDownloads.removeValue(forKey: songID) else { continue }
            guard inProgress.contains(songID) else { continue }
            if downloadedIDs.contains(songID), immediatelyPlayableURL(for: song) != nil {
                pendingDownloads.removeValue(forKey: songID)
                _ = persistPendingDownloads()
                updatePublishedState { $0.inProgress.remove(songID) }
                continue
            }
            startDownloadTask(song: song)
        }
        queuedDownloadOrder.removeFirst(drainedCount)
    }

    private func startDownloadTask(song: Song) {
        guard let remote = song.audioURL else {
            finishDownload(songID: song.id, song: song, moved: false)
            return
        }
        let songID = song.id
        guard let token = pendingDownloads[songID]?.token else { return }
        let taskRegistry = taskRegistry
        taskRegistry.register(songID: songID, token: token)
        ensureSongDirectory(for: songID)
        let promotionTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let promoted = self.promotePlaybackCacheIfAvailable(
                for: song,
                remoteURL: remote,
                token: token
            )
            await MainActor.run { [weak self] in
                self?.finishCachePromotion(
                    song: song,
                    remoteURL: remote,
                    token: token,
                    promoted: promoted
                )
            }
        }
        cachePromotionTasks[songID] = promotionTask
    }

    private var activeDownloadWorkCount: Int {
        tasks.count + cachePromotionTasks.count
    }

    private nonisolated func promotePlaybackCacheIfAvailable(
        for song: Song,
        remoteURL: URL,
        token: UUID
    ) -> DownloadCachePromotion? {
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        guard let cachedURL = AudioCacheStore.playableMainURL(
            for: song.id,
            expectedRemoteURL: remoteURL,
            expectedDuration: expectedDuration
        ), !Task.isCancelled else { return nil }

        let songFiles = files(for: song.id, sourceURL: remoteURL)
        let stagedAudio = Self.promotionStagingURL(
            in: songFiles.directory,
            sourceURL: remoteURL,
            token: token
        )
        let stagedSource = songFiles.directory.appendingPathComponent(
            "main.source.promoting-\(token.uuidString)"
        )
        let fm = FileManager.default
        var keepStaging = false
        defer {
            if !keepStaging {
                try? fm.removeItem(at: stagedAudio)
                try? fm.removeItem(at: stagedSource)
            }
        }

        do {
            try fm.createDirectory(at: songFiles.directory, withIntermediateDirectories: true)
            try fm.copyItem(at: cachedURL, to: stagedAudio)
            guard !Task.isCancelled,
                  Self.isValidDownloadedAudio(at: stagedAudio, expectedDuration: expectedDuration),
                  let sourceData = remoteURL.absoluteString.data(using: .utf8)
            else { return nil }
            try sourceData.write(to: stagedSource, options: [.atomic])

            keepStaging = true
            return DownloadCachePromotion(
                stagedAudio: stagedAudio, stagedSource: stagedSource,
                audio: songFiles.audio, source: songFiles.source,
                directory: songFiles.directory
            )
        } catch {
            DebugLogger.log(
                "Playback cache promotion failed for \(song.id): \(error.localizedDescription)",
                category: .cache
            )
            return nil
        }
    }

    private func finishCachePromotion(
        song: Song,
        remoteURL: URL,
        token: UUID,
        promoted: DownloadCachePromotion?
    ) {
        // A cancelled promotion may finish after the same song is queued
        // again. It must not remove the replacement task's concurrency slot.
        let isCurrentTask = taskRegistry.performIfActive(songID: song.id, token: token) { true } ?? false
        // No suspension between token validation, publishing files, and
        // finishing the download: cancel/retry cannot interleave here.
        let committed = (try? promoted?.commit(ifCurrent: isCurrentTask)) ?? false
        guard isCurrentTask else { return }
        cachePromotionTasks.removeValue(forKey: song.id)
        if committed {
            DebugLogger.log("Download promoted from playback cache: \(song.id)", category: .cache)
            finishDownload(songID: song.id, song: song, moved: true, token: token)
            return
        }

        guard inProgress.contains(song.id) else {
            startQueuedDownloadsIfPossible()
            logDownloadQueueCompletionIfNeeded()
            return
        }
        startNetworkDownload(song: song, remoteURL: remoteURL, token: token)
    }

    private func startNetworkDownload(song: Song, remoteURL: URL, token: UUID, resumeData: Data? = nil) {
        let task = if let resumeData {
            downloadSession.downloadTask(withResumeData: resumeData)
        } else {
            downloadSession.downloadTask(with: remoteURL)
        }
        task.taskDescription = token.uuidString
        tasks[song.id] = task
        task.resume()
    }

    @concurrent
    private static func runCompletion(
        _ completion: @Sendable (URL?, URLResponse?, Error?) async -> Void,
        file: URL?, response: URLResponse?, error: Error?
    ) async {
        await completion(file, response, error)
    }

    private func downloadCompletion(song: Song, remoteURL: URL, token: UUID)
        -> @Sendable (URL?, URLResponse?, Error?) async -> Void {
        let songID = song.id
        let songFiles = files(for: songID, sourceURL: remoteURL)
        let taskRegistry = taskRegistry
        DebugLogger.log(
            "Download processing completion: \(songID)",
            category: .network
        )
        let completion: @Sendable (URL?, URLResponse?, Error?) async -> Void = { [weak self] tempURL, response, error in
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
                    moved = try taskRegistry.performIfActive(songID: songID, token: token) {
                        try FileManager.default.createDirectory(
                            at: songFiles.directory,
                            withIntermediateDirectories: true
                        )
                        try Self.commitDownloadedAudioFile(
                            at: tempURL,
                            to: songFiles.audio,
                            in: songFiles.directory
                        )
                        do {
                            try Data(remoteURL.absoluteString.utf8).write(
                                to: songFiles.source,
                                options: [.atomic]
                            )
                        } catch {
                            try? FileManager.default.removeItem(at: songFiles.audio)
                            throw error
                        }
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
                if let error {
                    let nsError = error as NSError
                    if nsError.code != NSURLErrorCancelled {
                        DebugLogger.log(
                            "Download transport failed for \(songID): domain=\(nsError.domain), code=\(nsError.code)",
                            category: .network
                        )
                        // An interrupted transfer carries resume data; continue
                        // from the partial bytes instead of failing the download.
                        if let resumeData = Self.resumeData(from: error) {
                            await MainActor.run { [weak self, song, token] in
                                self?.retryDownload(
                                    resumeData: resumeData,
                                    song: song,
                                    remoteURL: remoteURL,
                                    token: token
                                )
                            }
                            return
                        }
                    }
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    DebugLogger.log(
                        "Download rejected invalid audio for \(songID): status=\(status), bytes=\(downloadedBytes), expectedBytes=\(expectedBytes)",
                        category: .network
                    )
                }
            }
            await MainActor.run { [weak self, moved, song, songID, token] in
                self?.finishDownload(songID: songID, song: song, moved: moved, token: token)
            }
        }
        return completion
    }

    /// Resume data URLSession attaches to an interrupted download's error; nil
    /// for cancellations (user-initiated) and failures with no usable progress.
    nonisolated static func resumeData(from error: Error) -> Data? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain, nsError.code != NSURLErrorCancelled else {
            return nil
        }
        return nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    }

    private func retryDownload(resumeData: Data, song: Song, remoteURL: URL, token: UUID) {
        guard tasks[song.id] != nil, !resumeRetriedSongIDs.contains(song.id) else {
            finishDownload(songID: song.id, song: song, moved: false, token: token)
            return
        }
        resumeRetriedSongIDs.insert(song.id)
        DebugLogger.log("Resuming interrupted download: \(song.id)", category: .network)
        startNetworkDownload(song: song, remoteURL: remoteURL, token: token, resumeData: resumeData)
    }

    private func finishDownload(songID: String, song: Song, moved: Bool, token: UUID? = nil) {
        if let token {
            let isCurrentTask = taskRegistry.performIfActive(songID: songID, token: token) { true } ?? false
            guard isCurrentTask else {
                startQueuedDownloadsIfPossible()
                logDownloadQueueCompletionIfNeeded()
                return
            }
            taskRegistry.cancel(songID: songID)
        }
        pendingDownloads.removeValue(forKey: songID)
        _ = persistPendingDownloads()
        tasks.removeValue(forKey: songID)
        cachePromotionTasks.removeValue(forKey: songID)
        resumeRetriedSongIDs.remove(songID)
        let wasInProgress = inProgress.contains(songID)
        guard wasInProgress else {
            startQueuedDownloadsIfPossible()
            logDownloadQueueCompletionIfNeeded()
            return
        }
        if moved {
            writeMetadata(for: song)
            downloadedMetadata[songID] = song
            cacheValidDownload(songID: songID,
                audioURL: files(for: songID, sourceURL: song.audioURL).audio,
                source: song.audioURL?.absoluteString,
                expectedDuration: song.duration > 0 ? TimeInterval(song.duration) : nil)
            completedInCurrentQueue += 1
            // A downloaded song should never need the network again — but the
            // audio was the only thing being persisted, so its artwork was
            // still fetched on demand and showed a placeholder offline. Warm
            // the row and card variants into the (2 GB, 90-day) image cache so
            // the whole row renders from disk.
            ArtworkPrefetcher.shared.warmCollection(
                songs: [song],
                reason: "downloaded artwork \(songID)",
                variant: .row
            )
            ArtworkPrefetcher.shared.warmCollection(
                songs: [song],
                reason: "downloaded artwork card \(songID)",
                variant: .card
            )
        } else {
            failedInCurrentQueue += 1
            DebugLogger.log("Download failed: \(songID)", category: .network)
        }
        updatePublishedState { state in
            state.inProgress.remove(songID)
            if moved {
                state.downloadedIDs.insert(songID)
            }
        }
        startQueuedDownloadsIfPossible()
        logDownloadQueueCompletionIfNeeded()
    }

    func cancel(songID: String) {
        cancelWork(songID: songID)
        // Counts as an incomplete batch: without this a queue where the user
        // cancelled one song still satisfies `failedInCurrentQueue == 0` and
        // celebrates as though everything landed.
        cancelledInCurrentQueue += 1
        updatePublishedState { $0.inProgress.remove(songID) }
        startQueuedDownloadsIfPossible()
        logDownloadQueueCompletionIfNeeded()
    }

    func cancel(songs: [Song]) {
        let ids = Set(songs.map(\.id))
        let active = inProgress.intersection(ids)
        for id in ids { cancelWork(songID: id, persist: false) }
        _ = persistPendingDownloads()
        cancelledInCurrentQueue += active.count
        updatePublishedState { $0.inProgress.subtract(ids) }
        startQueuedDownloadsIfPossible()
        logDownloadQueueCompletionIfNeeded()
    }

    private func cancelWork(songID: String, persist: Bool = true) {
        cancellationGenerations[songID, default: 0] += 1
        pendingWiFiRepairs.removeValue(forKey: songID)
        if !pendingJournalLoaded { cancelledBeforePendingRestore.insert(songID) }
        deferredDownloadRequests.removeValue(forKey: songID)
        pendingDownloads.removeValue(forKey: songID)
        if persist { _ = persistPendingDownloads() }
        taskRegistry.cancel(songID: songID)
        cachePromotionTasks[songID]?.cancel()
        cachePromotionTasks.removeValue(forKey: songID)
        tasks[songID]?.cancel()
        tasks.removeValue(forKey: songID)
        resumeRetriedSongIDs.remove(songID)
        queuedDownloads.removeValue(forKey: songID)
        queuedDownloadOrder.removeAll { $0 == songID }
    }

    func remove(songID: String) {
        remove(songIDs: [songID])
    }

    func remove(songIDs: [String]) {
        removedDuringRestoration.formUnion(songIDs)
        let uniqueSongIDs = Set(songIDs)
        guard !uniqueSongIDs.isEmpty else { return }
        for songID in uniqueSongIDs {
            cancelWork(songID: songID)
            pendingWiFiRepairs.removeValue(forKey: songID)
            validDownloadCache.removeValue(forKey: songID)
            downloadedMetadata.removeValue(forKey: songID)
        }
        stageDownloadsForDeletion(songIDs: uniqueSongIDs)
        updatePublishedState { state in
            state.inProgress.subtract(uniqueSongIDs)
            state.downloadedIDs.subtract(uniqueSongIDs)
        }
        startQueuedDownloadsIfPossible()
        logDownloadQueueCompletionIfNeeded()
        DebugLogger.log("Downloads removed: \(uniqueSongIDs.count)", category: .network)
    }

    private func stageDownloadsForDeletion(songIDs: Set<String>) {
        let fm = FileManager.default
        let deletionDirectory = cacheDir.deletingLastPathComponent().appendingPathComponent(
            "\(Self.pendingDeletionPrefix)\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fm.createDirectory(at: deletionDirectory, withIntermediateDirectories: true)
        } catch {
            for songID in songIDs {
                removeDownloadFilesImmediately(songID: songID)
            }
            DebugLogger.log("Could not stage downloads for deletion: \(error)", category: .cache)
            return
        }

        var stagedAny = false
        for songID in songIDs {
            let storageKey = SongStorageKey.component(for: songID)
            let sources = [
                files(for: songID).directory,
                cacheDir.appendingPathComponent("\(storageKey).mp3"),
                cacheDir.appendingPathComponent("\(storageKey).source"),
                cacheDir.appendingPathComponent("\(storageKey).json"),
            ]
            for source in sources where fm.fileExists(atPath: source.path) {
                let destination = deletionDirectory.appendingPathComponent(source.lastPathComponent)
                do {
                    try fm.moveItem(at: source, to: destination)
                    stagedAny = true
                } catch {
                    try? fm.removeItem(at: source)
                    DebugLogger.log(
                        "Could not stage \(source.lastPathComponent) for deletion: \(error)",
                        category: .cache
                    )
                }
            }
        }
        guard stagedAny else {
            try? fm.removeItem(at: deletionDirectory)
            return
        }
        Self.deletionQueue.async {
            try? FileManager.default.removeItem(at: deletionDirectory)
        }
    }

    private func removeDownloadFilesImmediately(songID: String) {
        let fm = FileManager.default
        let storageKey = SongStorageKey.component(for: songID)
        try? fm.removeItem(at: files(for: songID).directory)
        try? fm.removeItem(at: cacheDir.appendingPathComponent("\(storageKey).mp3"))
        try? fm.removeItem(at: cacheDir.appendingPathComponent("\(storageKey).source"))
        try? fm.removeItem(at: cacheDir.appendingPathComponent("\(storageKey).json"))
    }

    func removeAll(completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) {
        let fm = FileManager.default
        let deletionDirectory = cacheDir.deletingLastPathComponent().appendingPathComponent(
            "\(Self.pendingDeletionPrefix)\(UUID().uuidString)",
            isDirectory: true
        )
        let suspendedTokens = taskRegistry.suspendAll()
        var stagedDirectory: URL?
        if fm.fileExists(atPath: cacheDir.path) {
            do {
                try fm.moveItem(at: cacheDir, to: deletionDirectory)
                stagedDirectory = deletionDirectory
            } catch let stagingError {
                do {
                    try fm.removeItem(at: cacheDir)
                } catch let deletionError {
                    taskRegistry.restore(suspendedTokens)
                    DebugLogger.log(
                        "Could not remove downloads: staging failed (\(stagingError)); deletion failed (\(deletionError))",
                        category: .network
                    )
                    completion(false)
                    return
                }
            }
        }

        do {
            try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            // Song-directory creation also recreates missing parents, so a
            // failed empty-directory recreation does not invalidate removal.
            DebugLogger.log("Could not recreate downloads directory: \(error)", category: .cache)
        }

        validationBatchGeneration += 1
        for task in tasks.values {
            task.cancel()
        }
        for task in cachePromotionTasks.values {
            task.cancel()
        }
        tasks.removeAll()
        cachePromotionTasks.removeAll()
        resumeRetriedSongIDs.removeAll()
        if !pendingJournalLoaded { discardPendingOnRestore = true }
        deferredDownloadRequests.removeAll()
        pendingDownloads.removeAll()
        _ = persistPendingDownloads()
        queuedDownloads.removeAll()
        queuedDownloadOrder.removeAll()
        isLoggingDownloadQueue = false
        completedInCurrentQueue = 0
        failedInCurrentQueue = 0
        cancelledInCurrentQueue = 0
        pendingWiFiRepairs.removeAll()
        validDownloadCache.removeAll()
        downloadedMetadata.removeAll()
        restorationGeneration += 1
        restorationState = .ready

        if let stagedDirectory {
            Self.deletionQueue.async {
                let success: Bool
                do {
                    try FileManager.default.removeItem(at: stagedDirectory)
                    success = true
                } catch {
                    success = !FileManager.default.fileExists(atPath: stagedDirectory.path)
                }
                Task { @MainActor in completion(success) }
            }
        } else if !fm.fileExists(atPath: cacheDir.path) {
            try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        updatePublishedState { state in
            state.downloadedIDs.removeAll()
            state.inProgress.removeAll()
        }
        DebugLogger.log("All downloads removed", category: .network)
        if stagedDirectory == nil { completion(true) }
    }

    nonisolated static func isPendingDeletionDirectoryName(_ name: String) -> Bool {
        name.hasPrefix(pendingDeletionPrefix)
    }

    private nonisolated static func removePendingDeletionDirectories(in parent: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries where isPendingDeletionDirectoryName(entry.lastPathComponent) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            try? fm.removeItem(at: entry)
        }
    }

    private func logDownloadQueueCompletionIfNeeded() {
        guard isLoggingDownloadQueue,
              tasks.isEmpty,
              cachePromotionTasks.isEmpty,
              queuedDownloadOrder.isEmpty
        else { return }
        DebugLogger.log(
            "Download queue complete: completed=\(completedInCurrentQueue), failed=\(failedInCurrentQueue)",
            category: .network
        )
        // A whole batch landing is worth a custom texture; a single song is
        // not — every download entry point is an explicit user action, so the
        // only thing separating "earned" from "noise" here is the batch size.
        if completedInCurrentQueue > 1, failedInCurrentQueue == 0, cancelledInCurrentQueue == 0 {
            AppHaptic.celebrate.play()
        }
        DownloadNotifications.shared.downloadsFinished(
            completed: completedInCurrentQueue, failed: failedInCurrentQueue
        )
        isLoggingDownloadQueue = false
        completedInCurrentQueue = 0
        failedInCurrentQueue = 0
        cancelledInCurrentQueue = 0
    }

    /// Read-only discovery. Live removals are excluded when this result is applied.
    nonisolated static func scanExistingDownloads(in cacheDir: URL) -> StartupScanResult {
        let fm = FileManager.default
        var ids = Set<String>()
        var metadataByID: [String: Song] = [:]
        var hadFailures = false
        do {
            let entries = try fm.contentsOfDirectory(at: cacheDir,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for entry in entries {
                do {
                    guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                        if entry.pathExtension == "json" {
                            let song = try JSONDecoder().decode(Song.self, from: Data(contentsOf: entry))
                            if try entry.deletingPathExtension().appendingPathExtension("mp3").checkResourceIsReachable() {
                                ids.insert(song.id)
                                metadataByID[song.id] = song
                            }
                        }
                        continue
                    }
                    let metadataURL = entry.appendingPathComponent("metadata.json")
                    let song = try JSONDecoder().decode(Song.self, from: Data(contentsOf: metadataURL))
                    // Discover committed audio without opening a decoder. A startup probe
                    // cannot establish corruption, and must never remove a user's download.
                    let audioFiles = try fm.contentsOfDirectory(at: entry,
                        includingPropertiesForKeys: [.isRegularFileKey]).filter { candidate in
                            guard candidate.lastPathComponent.hasPrefix("main."),
                                  !candidate.lastPathComponent.contains(".promoting-"),
                                  !candidate.lastPathComponent.contains(".partial."),
                                  AudioCacheStore.supportedMainAudioExtensions.contains(candidate.pathExtension.lowercased())
                            else { return false }
                            return try candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                        }
                    guard !audioFiles.isEmpty else { continue }
                    ids.insert(song.id)
                    metadataByID[song.id] = song
                } catch {
                    hadFailures = true
                    DebugLogger.log("Download restoration \(entry.path): \(error)", category: .cache)
                }
            }
        } catch {
            hadFailures = true
            DebugLogger.log("Download enumeration \(cacheDir.path): \(error)", category: .cache)
        }
        return StartupScanResult(hadFailures: hadFailures, validIDs: ids,
            metadata: metadataByID)
    }

    nonisolated static func removePromotionStagingFiles(
        in directory: URL,
        createdBefore cutoff: Date
    ) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries where entry.lastPathComponent.contains(".promoting-") {
            let modifiedAt = try? entry.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if let modifiedAt, modifiedAt > cutoff { continue }
            try? fm.removeItem(at: entry)
        }
    }

    nonisolated static func restorationMissingIDs(
        starting: Set<String>, discovered: Set<String>, changed: Set<String>,
        inProgress: Set<String>, hadFailures: Bool
    ) -> Set<String> {
        guard !hadFailures else { return [] }
        return starting.subtracting(discovered).subtracting(changed).subtracting(inProgress)
    }

    private func applyStartupScan(_ scan: StartupScanResult) {
        let restoredIDs = scan.validIDs.subtracting(removedDuringRestoration)
        for (songID, song) in scan.metadata where restoredIDs.contains(songID) && downloadedMetadata[songID] == nil {
            downloadedMetadata[songID] = song
        }
        let missingIDs = Self.restorationMissingIDs(starting: restorationStartingIDs,
            discovered: scan.validIDs, changed: changedDuringRestoration,
            inProgress: inProgress, hadFailures: scan.hadFailures)
        for songID in missingIDs {
            downloadedMetadata.removeValue(forKey: songID)
            validDownloadCache.removeValue(forKey: songID)
        }
        updatePublishedState(persist: false) {
            $0.downloadedIDs.subtract(missingIDs)
            $0.downloadedIDs.formUnion(restoredIDs)
        }
        if !scan.hadFailures { persistManifest() }
        restorationState = scan.hadFailures ? .failed : .ready
        DebugLogger.log("Download restoration: count=\(downloadedIDs.count), state=\(restorationState), protectedData=\(UIApplication.shared.isProtectedDataAvailable)", category: .cache)
    }

    nonisolated static func sameAudioResource(_ lhs: String, _ rhs: String) -> Bool {
        guard var left = URLComponents(string: lhs), var right = URLComponents(string: rhs) else { return lhs == rhs }
        // Only ignore known authentication parameters; content selectors remain identity.
        let signatures: Set<String> = ["token", "signature", "expires", "policy", "key-pair-id"]
        for key in [true, false] {
            var value = key ? left : right
            value.queryItems = value.queryItems?.filter {
                !signatures.contains($0.name.lowercased()) && !$0.name.lowercased().hasPrefix("x-amz-")
            }
            if value.queryItems?.isEmpty == true { value.queryItems = nil }
            value.fragment = nil
            if key { left = value } else { right = value }
        }
        return left == right
    }

    func playableURL(for song: Song) -> URL? {
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        // Fast path: a prewarmed validation entry needs only the
        // modification-date stat in hasCachedValidation, skipping the
        // migration and source-file reads below.
        if let cached = validDownloadCache[song.id],
           cached.source == song.audioURL?.absoluteString,
           let source = cached.source,
           let sourceURL = URL(string: source)
        {
            let audio = Self.downloadedAudioURL(
                in: downloadDirectory(for: song.id),
                sourceURL: sourceURL
            )
            if hasCachedValidation(
                for: song.id,
                audioURL: audio,
                source: source,
                expectedDuration: expectedDuration
            ) {
                downloadedMetadata[song.id] = song
                return audio
            }
        }
        migrateLegacyDownloadIfNeeded(for: song.id)
        migrateMislabeledDownloadedAudioIfNeeded(
            for: song.id,
            expectedSourceURL: song.audioURL
        )
        let cachedSource = readSourceURL(for: song.id)
        let storedSourceURL = cachedSource.flatMap(URL.init(string:))
        let songFiles = files(
            for: song.id,
            sourceURL: storedSourceURL ?? song.audioURL
        )
        guard FileManager.default.fileExists(atPath: songFiles.audio.path) else {
            return nil
        }
        let expectedSource = song.audioURL?.absoluteString
        if let cachedSource, let expectedSource, !Self.sameAudioResource(cachedSource, expectedSource) {
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
            downloadedMetadata[song.id] = song
            return songFiles.audio
        }
        guard let cachedSource else {
            if let expected = song.audioURL {
                writeSourceURL(expected, for: song.id)
                writeMetadata(for: song)
                downloadedMetadata[song.id] = song
                updatePublishedState { $0.downloadedIDs.insert(song.id) }
                DebugLogger.log(
                    "Repaired missing download source metadata for \(song.id)",
                    category: .cache
                )
            }
            guard Self.isValidDownloadedAudio(at: songFiles.audio, expectedDuration: expectedDuration) else {
                DebugLogger.log("Unable to validate downloaded audio for \(song.id)", category: .cache)
                DebugLogger.log("Keeping download after failed audio probe: \(song.id)", category: .cache)
                return nil
            }
            cacheValidDownload(
                songID: song.id,
                audioURL: songFiles.audio,
                source: expectedSource,
                expectedDuration: expectedDuration
            )
            downloadedMetadata[song.id] = song
            return songFiles.audio
        }
        guard Self.isValidDownloadedAudio(at: songFiles.audio, expectedDuration: expectedDuration) else {
            DebugLogger.log("Unable to validate downloaded audio for \(song.id)", category: .cache)
            DebugLogger.log("Keeping download after failed audio probe: \(song.id)", category: .cache)
            return nil
        }
        cacheValidDownload(
            songID: song.id,
            audioURL: songFiles.audio,
            source: cachedSource,
            expectedDuration: expectedDuration
        )
        downloadedMetadata[song.id] = song
        return songFiles.audio
    }

    func immediatelyPlayableURL(for song: Song) -> URL? {
        guard downloadedIDs.contains(song.id) else { return nil }
        let cachedSource = readSourceURL(for: song.id)
        let storedSourceURL = cachedSource.flatMap(URL.init(string:))
        let songFiles = files(
            for: song.id,
            sourceURL: storedSourceURL ?? song.audioURL
        )
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        let expectedSource = song.audioURL?.absoluteString
        guard cachedSource == nil || expectedSource == nil || Self.sameAudioResource(cachedSource!, expectedSource!),
              FileManager.default.fileExists(atPath: songFiles.audio.path),
              hasCachedValidation(
                  for: song.id,
                  audioURL: songFiles.audio,
                  source: cachedSource ?? expectedSource,
                  expectedDuration: expectedDuration
              )
        else { return nil }
        downloadedMetadata[song.id] = song
        return songFiles.audio
    }

    private func hasCachedValidation(
        for songID: String,
        audioURL: URL,
        source: String?,
        expectedDuration: TimeInterval?
    ) -> Bool {
        if validDownloadCache[songID] == nil {
            let receipt = audioURL.deletingLastPathComponent().appendingPathComponent("validation.json")
            if let data = try? Data(contentsOf: receipt),
               let cached = try? JSONDecoder().decode(ValidDownloadCacheEntry.self, from: data) {
                validDownloadCache[songID] = cached
            }
        }
        guard let cached = validDownloadCache[songID] else { return false }
        return Self.validationMatches(cached, audioURL: audioURL, source: source, expectedDuration: expectedDuration)
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
            modifiedAt: Self.modificationDate(at: audioURL),
            byteCount: Self.downloadedByteCount(at: audioURL)
        )
        do {
            try JSONEncoder().encode(validDownloadCache[songID]).write(
                to: audioURL.deletingLastPathComponent().appendingPathComponent("validation.json"), options: .atomic)
        } catch {
            DebugLogger.log("Download validation receipt write for \(songID): \(error)", category: .cache)
        }
    }

    nonisolated static func validationMatches(_ cached: ValidDownloadCacheEntry, audioURL: URL,
        source: String?, expectedDuration: TimeInterval?) -> Bool {
        let sameSource = cached.source == source || (cached.source != nil && source != nil
            && sameAudioResource(cached.source!, source!))
        guard sameSource, cached.expectedDuration == expectedDuration,
              let modified = cached.modifiedAt, modified == modificationDate(at: audioURL) else { return false }
        return cached.byteCount.map { $0 > 0 && $0 == downloadedByteCount(at: audioURL) } ?? true
    }

    /// Resolve committed downloads before consulting the separate streaming cache.
    /// Older installs have no receipt, so validate only the requested track off-main.
    func resolvedPlaybackURL(for song: Song) async throws -> URL? {
        if let ready = immediatelyPlayableURL(for: song) { return ready }
        let generation = cancellationGenerations[song.id, default: 0]
        let batchGeneration = validationBatchGeneration
        if downloadedIDs.contains(song.id), !UIApplication.shared.isProtectedDataAvailable {
            throw CocoaError(.fileReadNoPermission)
        }
        let sourceURL = readSourceURL(for: song.id).flatMap(URL.init(string:)) ?? song.audioURL
        if let sourceURL, let expected = song.audioURL,
           !Self.sameAudioResource(sourceURL.absoluteString, expected.absoluteString) { return nil }
        guard FileManager.default.fileExists(atPath: files(for: song.id, sourceURL: sourceURL).audio.path) else { return nil }
        let started = ContinuousClock.now
        let entries = await Task.detached(priority: .userInitiated) {
            self.validateDownloadsForCachePrewarm([song])
        }.value
        try Task.checkCancellation()
        guard cancellationGenerations[song.id, default: 0] == generation,
              validationBatchGeneration == batchGeneration else { throw CancellationError() }
        guard let entry = entries[song.id] else {
            DebugLogger.log("Keeping unreadable download without network fallback: \(song.id)", category: .cache)
            throw CocoaError(.fileReadUnknown)
        }
        let resolvedSourceURL = entry.source.flatMap(URL.init(string:)) ?? song.audioURL
        let audio = files(for: song.id, sourceURL: resolvedSourceURL).audio
        guard Self.validationMatches(entry, audioURL: audio, source: entry.source,
            expectedDuration: entry.expectedDuration) else { return nil }
        cacheValidDownload(songID: song.id, audioURL: audio, source: entry.source,
            expectedDuration: entry.expectedDuration)
        downloadedMetadata[song.id] = song
        updatePublishedState { $0.downloadedIDs.insert(song.id) }
        DebugLogger.log("Downloaded playback resolved: \(song.id), elapsed=\(started.duration(to: .now))", category: .playback)
        return audio
    }

    /// Returns true only when the on-disk download is conclusively invalid and was removed.
    /// Playback callbacks alone are not evidence that a download is corrupt.
    @discardableResult
    func repairIfDownloadedFileIsBroken(for song: Song) -> Bool {
        guard isDownloaded(song.id) else { return false }
        migrateMislabeledDownloadedAudioIfNeeded(
            for: song.id,
            expectedSourceURL: song.audioURL
        )
        let storedSourceURL = readSourceURL(for: song.id).flatMap(URL.init(string:))
        let songFiles = files(
            for: song.id,
            sourceURL: storedSourceURL ?? song.audioURL
        )
        guard FileManager.default.fileExists(atPath: songFiles.audio.path) else {
            return false
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        guard !Self.isValidDownloadedAudio(
            at: songFiles.audio,
            expectedDuration: expectedDuration
        ) else {
            return false
        }
        DebugLogger.log("Keeping download after failed audio probe: \(song.id)", category: .cache)
        return false
    }

    func downloadedSongs(knownSongs: [Song] = []) -> [Song] {
        var songsByID = downloadedMetadata
        for song in knownSongs where downloadedIDs.contains(song.id) {
            songsByID[song.id] = song
        }
        return downloadedIDs.compactMap { songsByID[$0] }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private nonisolated func readSourceURL(for songID: String) -> String? {
        readSourceURL(at: sourceURL(for: songID))
    }

    private nonisolated func readSourceURL(at sourceURL: URL) -> String? {
        guard let data = try? Data(contentsOf: sourceURL),
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

    /// Older builds stored every downloaded container as `main.mp3`. When the
    /// saved source identifies another supported container, rename the file
    /// before validation so Core Audio selects the correct decoder.
    private nonisolated func migrateMislabeledDownloadedAudioIfNeeded(
        for songID: String,
        expectedSourceURL: URL?
    ) {
        let persistedSourceURL = readSourceURL(for: songID).flatMap(URL.init(string:))
        guard let resolvedSourceURL = persistedSourceURL ?? expectedSourceURL,
              AudioCacheStore.mainAudioExtension(for: resolvedSourceURL) != "mp3"
        else { return }

        let directory = downloadDirectory(for: songID)
        let legacyAudio = directory.appendingPathComponent("main.mp3")
        let resolvedAudio = Self.downloadedAudioURL(
            in: directory,
            sourceURL: resolvedSourceURL
        )
        let fm = FileManager.default
        guard !fm.fileExists(atPath: resolvedAudio.path),
              fm.fileExists(atPath: legacyAudio.path)
        else { return }

        do {
            try fm.moveItem(at: legacyAudio, to: resolvedAudio)
            guard AudioCacheStore.isPlayableAudioFile(at: resolvedAudio) else {
                try? fm.moveItem(at: resolvedAudio, to: legacyAudio)
                return
            }
            DebugLogger.log(
                "Migrated downloaded audio container for \(songID) to .\(resolvedAudio.pathExtension)",
                category: .cache
            )
        } catch {
            if fm.fileExists(atPath: resolvedAudio.path),
               !fm.fileExists(atPath: legacyAudio.path)
            {
                try? fm.moveItem(at: resolvedAudio, to: legacyAudio)
            }
        }
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
        cancelWork(songID: song.id)
        let songFiles = files(for: song.id, sourceURL: song.audioURL)
        validDownloadCache.removeValue(forKey: song.id)
        downloadedMetadata.removeValue(forKey: song.id)
        Self.removeDownloadedAudioFiles(in: songFiles.directory)
        try? FileManager.default.removeItem(at: songFiles.source)
        let storageKey = SongStorageKey.component(for: song.id)
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("\(storageKey).mp3"))
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("\(storageKey).source"))
        updatePublishedState { state in
            state.inProgress.remove(song.id)
            state.downloadedIDs.remove(song.id)
        }
        startQueuedDownloadsIfPossible()
        logDownloadQueueCompletionIfNeeded()
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
        download(songs: repairs)
    }

    private nonisolated func writeMetadata(for song: Song) {
        let songFiles = files(for: song.id)
        ensureSongDirectory(for: song.id)
        guard let data = try? JSONEncoder().encode(song) else { return }
        try? data.write(to: songFiles.metadata, options: [.atomic])
    }

    private nonisolated func readMetadata(for songID: String) -> Song? {
        readMetadata(at: files(for: songID).metadata)
    }

    private nonisolated func readMetadata(at metadataURL: URL) -> Song? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(Song.self, from: data)
    }

    private nonisolated func migrateLegacyDownloadIfNeeded(for songID: String) {
        let fm = FileManager.default
        let storageKey = SongStorageKey.component(for: songID)
        let legacyAudio = cacheDir.appendingPathComponent("\(storageKey).mp3")
        guard fm.fileExists(atPath: legacyAudio.path),
              let sourceValue = readLegacySourceURL(for: songID),
              let remoteURL = URL(string: sourceValue) else { return }
        let songFiles = files(for: songID, sourceURL: remoteURL)
        guard !fm.fileExists(atPath: songFiles.audio.path) else { return }
        do {
            try fm.createDirectory(at: songFiles.directory, withIntermediateDirectories: true)
            try fm.copyItem(at: legacyAudio, to: songFiles.audio)
            try Data(sourceValue.utf8).write(to: songFiles.source, options: .atomic)
            let legacyMetadata = cacheDir.appendingPathComponent("\(storageKey).json")
            if !fm.fileExists(atPath: songFiles.metadata.path), fm.fileExists(atPath: legacyMetadata.path) {
                try fm.copyItem(at: legacyMetadata, to: songFiles.metadata)
            }
            // Preserve the original until explicit removal; a decoder failure
            // or interrupted migration must not destroy the only good copy.
        } catch {
            DebugLogger.log("Legacy download migration \(songID): \(error)", category: .cache)
        }
    }

    private nonisolated func readLegacySourceURL(for songID: String) -> String? {
        let storageKey = SongStorageKey.component(for: songID)
        let legacySource = cacheDir.appendingPathComponent("\(storageKey).source")
        guard let data = try? Data(contentsOf: legacySource),
              let rawValue = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
