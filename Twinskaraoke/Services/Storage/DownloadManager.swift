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

    private struct ValidDownloadCacheEntry {
        let source: String?
        let expectedDuration: TimeInterval?
        let modifiedAt: Date?
    }

    private struct StartupScanResult {
        let validIDs: Set<String>
        let validEntries: [String: ValidDownloadCacheEntry]
        let metadata: [String: Song]
        let repairs: [String: Song]
        let junkDirectories: [URL]
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
    private var pendingWiFiRepairs: [String: Song] = [:]
    private var validDownloadCache: [String: ValidDownloadCacheEntry] = [:]
    private var downloadedMetadata: [String: Song] = [:]
    private var isWiFiAvailable = false
    private let taskRegistry = DownloadTaskRegistry()
    private let downloadSession: URLSession
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "DownloadManager.NetworkMonitor")
    private nonisolated static let deletionQueue = DispatchQueue(
        label: "DownloadManager.Deletion",
        qos: .utility
    )
    private nonisolated static let pendingDeletionPrefix = "Downloads.pending-delete-"
    private nonisolated static let maxConcurrentDownloads = 3

    private init() {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpMaximumConnectionsPerHost = Self.maxConcurrentDownloads
        sessionConfiguration.waitsForConnectivity = true
        sessionConfiguration.timeoutIntervalForRequest = 60
        sessionConfiguration.timeoutIntervalForResource = 30 * 60
        downloadSession = URLSession(configuration: sessionConfiguration)
        cacheDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let downloadsParent = cacheDir.deletingLastPathComponent()
        Self.deletionQueue.async {
            Self.removePendingDeletionDirectories(in: downloadsParent)
        }
        startNetworkMonitoring()
        // The startup scan opens every downloaded audio file to validate it;
        // that per-file decode work must stay off the main thread at launch.
        let scanStartedAt = Date()
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let scan = scanExistingDownloadsBlocking(createdBefore: scanStartedAt)
            await MainActor.run {
                self.applyStartupScan(scan)
            }
        }
    }

    deinit {
        for task in cachePromotionTasks.values {
            task.cancel()
        }
        downloadSession.invalidateAndCancel()
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

    private func updatePublishedState(_ update: (inout PublishedState) -> Void) {
        let previous = publishedState
        var next = previous
        update(&next)
        guard next != previous else { return }
        publishedState = next
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
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let entries = self.validateDownloadsForCachePrewarm(songs)
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (songID, entry) in entries where self.validDownloadCache[songID] == nil {
                    self.validDownloadCache[songID] = entry
                }
                self.enqueueDownloads(songs)
            }
        }
    }

    /// Mirrors the early-exit checks in playableURL so warmed cache entries
    /// make it return the audio file without AVAudioFile on the main actor.
    /// Missing, stale, or invalid downloads get no entry and fall back to the
    /// on-main validation and repair path.
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
            if let cachedSource, let expectedSource, cachedSource != expectedSource { continue }
            guard Self.isValidDownloadedAudio(
                at: songFiles.audio,
                expectedDuration: expectedDuration
            ) else { continue }
            entries[song.id] = ValidDownloadCacheEntry(
                source: cachedSource ?? expectedSource,
                expectedDuration: expectedDuration,
                modifiedAt: Self.modificationDate(at: songFiles.audio)
            )
        }
        return entries
    }

    private func enqueueDownloads(_ songs: [Song]) {
        var nextInProgress = inProgress
        var acceptedAny = false

        for song in songs {
            guard song.audioURL != nil else { continue }
            if downloadedIDs.contains(song.id), playableURL(for: song) != nil { continue }
            guard !nextInProgress.contains(song.id) else { continue }

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
            DebugLogger.log("Download queue started", category: .network)
        }
        updatePublishedState { $0.inProgress = nextInProgress }
        startQueuedDownloadsIfPossible()
    }

    private func startQueuedDownloadsIfPossible() {
        // Iterate by index and remove the drained prefix in one batch instead
        // of removeFirst() per element, which shifts the whole array each time.
        var drainedCount = 0
        while activeDownloadWorkCount < Self.maxConcurrentDownloads,
              drainedCount < queuedDownloadOrder.count
        {
            let songID = queuedDownloadOrder[drainedCount]
            drainedCount += 1
            guard let song = queuedDownloads.removeValue(forKey: songID) else { continue }
            guard inProgress.contains(songID), !downloadedIDs.contains(songID) else {
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
        let token = UUID()
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
    ) -> Bool {
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        guard let cachedURL = AudioCacheStore.playableMainURL(
            for: song.id,
            expectedRemoteURL: remoteURL,
            expectedDuration: expectedDuration
        ), !Task.isCancelled else { return false }

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
        defer {
            try? fm.removeItem(at: stagedAudio)
            try? fm.removeItem(at: stagedSource)
        }

        do {
            try fm.createDirectory(at: songFiles.directory, withIntermediateDirectories: true)
            try fm.copyItem(at: cachedURL, to: stagedAudio)
            guard !Task.isCancelled,
                  Self.isValidDownloadedAudio(at: stagedAudio, expectedDuration: expectedDuration),
                  let sourceData = remoteURL.absoluteString.data(using: .utf8)
            else { return false }
            try sourceData.write(to: stagedSource, options: [.atomic])

            return try taskRegistry.performIfActive(songID: song.id, token: token) {
                try Self.commitDownloadedAudioFile(
                    at: stagedAudio,
                    to: songFiles.audio,
                    in: songFiles.directory
                )
                if fm.fileExists(atPath: songFiles.source.path) {
                    do {
                        _ = try fm.replaceItemAt(songFiles.source, withItemAt: stagedSource)
                    } catch {
                        try? fm.removeItem(at: songFiles.audio)
                        throw error
                    }
                } else {
                    do {
                        try fm.moveItem(at: stagedSource, to: songFiles.source)
                    } catch {
                        try? fm.removeItem(at: songFiles.audio)
                        throw error
                    }
                }
                return true
            } ?? false
        } catch {
            DebugLogger.log(
                "Playback cache promotion failed for \(song.id): \(error.localizedDescription)",
                category: .cache
            )
            return false
        }
    }

    private func finishCachePromotion(
        song: Song,
        remoteURL: URL,
        token: UUID,
        promoted: Bool
    ) {
        cachePromotionTasks.removeValue(forKey: song.id)
        if promoted {
            DebugLogger.log("Download promoted from playback cache: \(song.id)", category: .cache)
            finishDownload(songID: song.id, song: song, moved: true, token: token)
            return
        }

        let isCurrentTask = taskRegistry.performIfActive(songID: song.id, token: token) { true } ?? false
        guard isCurrentTask, inProgress.contains(song.id) else {
            startQueuedDownloadsIfPossible()
            logDownloadQueueCompletionIfNeeded()
            return
        }
        startNetworkDownload(song: song, remoteURL: remoteURL, token: token)
    }

    private func startNetworkDownload(song: Song, remoteURL: URL, token: UUID, resumeData: Data? = nil) {
        let songID = song.id
        let songFiles = files(for: songID, sourceURL: remoteURL)
        let taskRegistry = taskRegistry
        DebugLogger.log(
            "Download started: \(songID) (active=\(tasks.count + 1), queued=\(queuedDownloadOrder.count))",
            category: .network
        )
        let completion: @Sendable (URL?, URLResponse?, Error?) -> Void = { [weak self] tempURL, response, error in
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
                            Task { @MainActor [weak self, song, token] in
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
            Task { @MainActor [weak self, moved, song, songID, token] in
                self?.finishDownload(songID: songID, song: song, moved: moved, token: token)
            }
        }
        let task = if let resumeData {
            downloadSession.downloadTask(withResumeData: resumeData, completionHandler: completion)
        } else {
            downloadSession.downloadTask(with: remoteURL, completionHandler: completion)
        }
        tasks[songID] = task
        task.resume()
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
                if moved {
                    let songFiles = files(for: songID, sourceURL: song.audioURL)
                    Self.removeDownloadedAudioFiles(in: songFiles.directory)
                    try? FileManager.default.removeItem(at: songFiles.source)
                }
                startQueuedDownloadsIfPossible()
                logDownloadQueueCompletionIfNeeded()
                return
            }
            taskRegistry.cancel(songID: songID)
        }
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
            validDownloadCache[songID] = ValidDownloadCacheEntry(
                source: song.audioURL?.absoluteString,
                expectedDuration: song.duration > 0 ? TimeInterval(song.duration) : nil,
                modifiedAt: Self.modificationDate(
                    at: files(for: songID, sourceURL: song.audioURL).audio
                )
            )
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
        updatePublishedState { $0.inProgress.remove(songID) }
        startQueuedDownloadsIfPossible()
        logDownloadQueueCompletionIfNeeded()
    }

    private func cancelWork(songID: String) {
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

    func removeAll() {
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

        for task in tasks.values {
            task.cancel()
        }
        for task in cachePromotionTasks.values {
            task.cancel()
        }
        tasks.removeAll()
        cachePromotionTasks.removeAll()
        resumeRetriedSongIDs.removeAll()
        queuedDownloads.removeAll()
        queuedDownloadOrder.removeAll()
        isLoggingDownloadQueue = false
        completedInCurrentQueue = 0
        failedInCurrentQueue = 0
        pendingWiFiRepairs.removeAll()
        validDownloadCache.removeAll()
        downloadedMetadata.removeAll()

        if let stagedDirectory {
            Self.deletionQueue.async {
                try? FileManager.default.removeItem(at: stagedDirectory)
            }
        } else if !fm.fileExists(atPath: cacheDir.path) {
            try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        updatePublishedState { state in
            state.downloadedIDs.removeAll()
            state.inProgress.removeAll()
        }
        DebugLogger.log("All downloads removed", category: .network)
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
        if completedInCurrentQueue > 1, failedInCurrentQueue == 0 {
            AppHaptic.celebrate.play()
        }
        isLoggingDownloadQueue = false
        completedInCurrentQueue = 0
        failedInCurrentQueue = 0
    }

    /// The scan runs concurrently with live downloads. It only removes
    /// promotion staging files that predate this launch; all other destructive
    /// cleanup is deferred to `applyStartupScan` so live state wins.
    private nonisolated func scanExistingDownloadsBlocking(
        createdBefore scanStartedAt: Date
    ) -> StartupScanResult {
        migrateLegacyDownloadsIfNeeded()
        let fm = FileManager.default
        var ids = Set<String>()
        var validEntries: [String: ValidDownloadCacheEntry] = [:]
        var metadataByID: [String: Song] = [:]
        var repairs: [String: Song] = [:]
        var junkDirectories: [URL] = []
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        else {
            return StartupScanResult(
                validIDs: ids,
                validEntries: validEntries,
                metadata: metadataByID,
                repairs: repairs,
                junkDirectories: junkDirectories
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
            Self.removePromotionStagingFiles(in: entry, createdBefore: scanStartedAt)
            // Read from the directory itself because unsafe IDs are stored under a hash.
            let metadata = readMetadata(at: entry.appendingPathComponent("metadata.json"))
            let directoryKey = entry.lastPathComponent
            let canRecoverSongID = SongStorageKey.component(for: directoryKey) == directoryKey
            guard let songID = metadata?.id ?? (canRecoverSongID ? directoryKey : nil) else {
                junkDirectories.append(entry)
                continue
            }
            migrateMislabeledDownloadedAudioIfNeeded(
                for: songID,
                expectedSourceURL: metadata?.audioURL
            )
            if hasValidDownload(for: songID) {
                ids.insert(songID)
                if let metadata {
                    metadataByID[songID] = metadata
                }
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
                    junkDirectories.append(entry)
                }
            }
        }
        return StartupScanResult(
            validIDs: ids,
            validEntries: validEntries,
            metadata: metadataByID,
            repairs: repairs,
            junkDirectories: junkDirectories
        )
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

    private func applyStartupScan(_ scan: StartupScanResult) {
        // Downloads may have started, finished, or been removed while the
        // scan ran; merge instead of overwriting, and let live state win.
        let fm = FileManager.default
        let stillExistingIDs = scan.validIDs.filter { songID in
            fm.fileExists(atPath: files(for: songID).audio.path)
        }
        for (songID, entry) in scan.validEntries
            where stillExistingIDs.contains(songID) && validDownloadCache[songID] == nil
        {
            validDownloadCache[songID] = entry
        }
        for (songID, song) in scan.metadata
            where stillExistingIDs.contains(songID) && downloadedMetadata[songID] == nil
        {
            downloadedMetadata[songID] = song
        }
        updatePublishedState { $0.downloadedIDs.formUnion(stillExistingIDs) }
        var repairCount = 0
        for (songID, song) in scan.repairs {
            guard !downloadedIDs.contains(songID), !inProgress.contains(songID) else { continue }
            // A missing metadata file means the song was removed during the
            // scan; don't delete anything or resurrect it as a repair.
            let songFiles = files(for: songID, sourceURL: song.audioURL)
            guard fm.fileExists(atPath: songFiles.metadata.path) else { continue }
            Self.removeDownloadedAudioFiles(in: songFiles.directory)
            try? fm.removeItem(at: songFiles.source)
            pendingWiFiRepairs[songID] = song
            repairCount += 1
        }
        let liveStorageKeys = SongStorageKey.components(
            for: downloadedIDs.union(inProgress)
        )
        for directory in scan.junkDirectories
            where !liveStorageKeys.contains(directory.lastPathComponent)
        {
            try? fm.removeItem(at: directory)
        }
        DebugLogger.log(
            "DownloadManager scan complete — \(downloadedIDs.count) existing downloads, \(repairCount) pending repair(s)",
            category: .network
        )
        startPendingWiFiRepairsIfPossible()
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
            discardBrokenDownloadAndScheduleRepair(for: song, reason: "audio file is missing")
            return nil
        }
        let expectedSource = song.audioURL?.absoluteString
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
            downloadedMetadata[song.id] = song
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
        guard FileManager.default.fileExists(atPath: songFiles.audio.path),
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
        var songsByID = downloadedMetadata
        for song in knownSongs where downloadedIDs.contains(song.id) {
            songsByID[song.id] = song
        }
        return downloadedIDs.compactMap { songsByID[$0] }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private nonisolated func hasValidDownload(for songID: String) -> Bool {
        let metadata = readMetadata(for: songID)
        migrateMislabeledDownloadedAudioIfNeeded(
            for: songID,
            expectedSourceURL: metadata?.audioURL
        )
        let songFiles = files(for: songID)
        guard FileManager.default.fileExists(atPath: songFiles.audio.path) else { return false }
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
        let storageKey = SongStorageKey.component(for: songID)
        let legacyAudio = cacheDir.appendingPathComponent("\(storageKey).mp3")
        let legacySource = cacheDir.appendingPathComponent("\(storageKey).source")
        guard fm.fileExists(atPath: legacyAudio.path) || fm.fileExists(atPath: legacySource.path) else {
            return
        }

        if hasValidDownload(for: songID) {
            try? fm.removeItem(at: legacyAudio)
            try? fm.removeItem(at: legacySource)
            try? fm.removeItem(at: cacheDir.appendingPathComponent("\(storageKey).json"))
            return
        }

        guard let sourceValue = readLegacySourceURL(for: songID),
              let remoteURL = URL(string: sourceValue),
              fm.fileExists(atPath: legacyAudio.path)
        else {
            try? fm.removeItem(at: legacyAudio)
            try? fm.removeItem(at: legacySource)
            return
        }

        let songFiles = files(for: songID, sourceURL: remoteURL)
        ensureSongDirectory(for: songID)
        Self.removeDownloadedAudioFiles(in: songFiles.directory)
        try? fm.removeItem(at: songFiles.source)

        do {
            try fm.moveItem(at: legacyAudio, to: songFiles.audio)
            guard AudioCacheStore.isPlayableAudioFile(at: songFiles.audio) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            fm.createFile(atPath: songFiles.source.path, contents: sourceValue.data(using: .utf8))
            try? fm.removeItem(at: legacySource)
            DebugLogger.log("Migrated legacy download into UUID folder for \(songID)", category: .cache)
        } catch {
            try? fm.removeItem(at: songFiles.audio)
            try? fm.removeItem(at: songFiles.source)
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
