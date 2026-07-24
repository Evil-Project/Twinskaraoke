import AVFoundation
import Combine
import CoreML
import Foundation
import Spleeter

extension Notification.Name {
    static let vocalSeparatorDidCacheStems = Notification.Name("VocalSeparatorDidCacheStems")
}

enum DeviceCapability {
    static var supportsKaraoke: Bool {
        if #available(iOS 18.0, *) {
            VocalSeparator.shared.isAvailable
        } else {
            false
        }
    }
}

enum VocalSeparatorError: Error {
    case unavailable
    case cancelled
    case modelMissing
    case trimFailed
    case readFailed
}

nonisolated struct CachedStems {
    let vocals: URL
    let instruments: URL
    let startOffset: TimeInterval
    let isTemporary: Bool

    init(vocals: URL, instruments: URL, startOffset: TimeInterval, isTemporary: Bool = false) {
        self.vocals = vocals
        self.instruments = instruments
        self.startOffset = startOffset
        self.isTemporary = isTemporary
    }
}

struct SeparationJobOwnership {
    private(set) var activeID: UUID?

    @discardableResult
    mutating func begin(id: UUID = UUID()) -> UUID {
        activeID = id
        return id
    }

    mutating func cancelCurrent() {
        activeID = nil
    }

    func owns(_ id: UUID) -> Bool {
        activeID == id
    }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        return true
    }
}

@MainActor
final class VocalSeparator: ObservableObject {
    static let shared = VocalSeparator()

    private enum SeparationTaskKind {
        case foreground
        case background
    }

    @Published private(set) var processingSongID: String?
    @Published private(set) var progressFraction: Float = 0
    @Published private(set) var isBackgroundAnalyzing: Bool = false

    let isAvailable: Bool
    private let modelURL: URL?
    private var activeTask: Task<URL, Error>?
    private var activeTaskKind: SeparationTaskKind?
    private var backgroundAnalysisTask: Task<Void, Never>?
    private var realtimeCleanupTask: Task<Void, Never>?
    private var jobOwnership = SeparationJobOwnership()

    private nonisolated static var realtimeTempDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealtimeStems", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func separationOutputURLs(
        in directory: URL, songID: String, jobID: UUID
    ) -> (vocals: URL, instruments: URL) {
        let storageKey = SongStorageKey.component(for: songID)
        let prefix = "\(storageKey).\(jobID.uuidString)"
        return (
            directory.appendingPathComponent("\(prefix).vocals.wav"),
            directory.appendingPathComponent("\(prefix).instruments.wav")
        )
    }

    private init() {
        let url = Bundle.main.url(forResource: "Spleeter2Model", withExtension: "mlmodelc")
        modelURL = url
        if #available(iOS 18.0, *) {
            isAvailable = (url != nil)
        } else {
            isAvailable = false
        }
        DebugLogger.log(
            "VocalSeparator init — available: \(isAvailable), model: \(url?.lastPathComponent ?? "nil")",
            category: .separation
        )
    }

    private func validCachedURL(_ url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size > 44
        else { return nil }
        return url
    }

    func cachedVocalsURL(forSongID songID: String) -> URL? {
        let url = AudioCacheStore.files(for: songID).vocals
        return validCachedURL(url) ?? validCachedURL(AudioCacheStore.compressedURL(for: url))
    }

    func cachedInstrumentsURL(forSongID songID: String) -> URL? {
        let url = AudioCacheStore.files(for: songID).instruments
        return validCachedURL(url) ?? validCachedURL(AudioCacheStore.compressedURL(for: url))
    }

    private func removeCachedStems(forSongID songID: String) {
        AudioCacheStore.removeStemCache(for: songID)
    }

    func cachedStems(
        forSongID songID: String,
        expectedDuration: TimeInterval? = nil
    ) -> CachedStems? {
        let offset = AudioCacheStore.readStartOffset(for: songID)
        guard offset <= 1.0 else {
            DebugLogger.log(
                "Discarding legacy partial stem cache for \(songID) (offset=\(offset))",
                category: .separation
            )
            removeCachedStems(forSongID: songID)
            return nil
        }
        guard
            let stems = AudioCacheStore.playableStems(
                for: songID,
                startOffset: offset,
                expectedDuration: expectedDuration
            )
        else {
            return nil
        }
        DebugLogger.log("Cache hit for stems: \(songID)", category: .separation)
        CacheManager.shared.recordAccess(for: stems.vocals)
        CacheManager.shared.recordAccess(for: stems.instruments)
        return stems
    }

    func cachedStartOffset(forSongID songID: String) -> TimeInterval {
        AudioCacheStore.readStartOffset(for: songID)
    }

    func separate(
        forSongID songID: String, sourceURL: URL, initiatedByBackground: Bool = false
    ) async throws -> CachedStems {
        let expectedDuration = Self.expectedDuration(for: sourceURL)
        if let cached = cachedStems(forSongID: songID, expectedDuration: expectedDuration) {
            return cached
        }
        guard isAvailable, let modelURL else { throw VocalSeparatorError.unavailable }
        if processingSongID == songID, let active = activeTask {
            DebugLogger.log("Waiting for in-progress separation: \(songID)", category: .separation)
            _ = try await active.value
            if let cached = cachedStems(forSongID: songID, expectedDuration: expectedDuration) {
                return cached
            }
            throw VocalSeparatorError.unavailable
        }
        if let old = activeTask {
            old.cancel()
            activeTask = nil
            activeTaskKind = nil
            processingSongID = nil
            progressFraction = 0
            jobOwnership.cancelCurrent()
        }
        try Task.checkCancellation()
        guard #available(iOS 18.0, *) else { throw VocalSeparatorError.unavailable }
        DebugLogger.log("Starting full separation for \(songID)", category: .separation)
        processingSongID = songID
        activeTaskKind = initiatedByBackground ? .background : .foreground
        let jobID = jobOwnership.begin()
        _ = AudioCacheStore.ensureSongDirectory(for: songID)
        let songFiles = AudioCacheStore.files(for: songID)
        let vocalsURL = songFiles.vocals
        let instrumentsURL = songFiles.instruments
        let staging = Self.separationOutputURLs(
            in: vocalsURL.deletingLastPathComponent(),
            songID: songID,
            jobID: jobID
        )
        let modelRef = modelURL
        let task = Task<URL, Error>.detached(priority: .utility) {
            do {
                try await Self.runSeparation2(
                    modelURL: modelRef,
                    jobID: jobID,
                    sourceURL: sourceURL,
                    vocalsOutputURL: staging.vocals,
                    instrumentsOutputURL: staging.instruments
                ) { fraction in
                    await VocalSeparator.shared.updateProgress(
                        jobID: jobID, songID: songID, fraction: fraction
                    )
                }
                try Task.checkCancellation()
                try await VocalSeparator.shared.publishCompletedFullJob(
                    jobID: jobID,
                    songID: songID,
                    staging: staging,
                    destinations: (vocalsURL, instrumentsURL)
                )
                return vocalsURL
            } catch {
                Self.cleanupTmpFiles([staging.vocals, staging.instruments])
                await VocalSeparator.shared.finishJob(jobID: jobID)
                throw error
            }
        }
        activeTask = task
        _ = try await task.value
        CacheManager.shared.enforceMusicCacheLimits()
        guard let stems = cachedStems(forSongID: songID, expectedDuration: expectedDuration) else {
            throw VocalSeparatorError.unavailable
        }
        DebugLogger.log("Full separation complete for \(songID)", category: .separation)
        return stems
    }

    func separateRealTime(
        forSongID songID: String, sourceURL: URL, fromTime: TimeInterval
    ) async throws -> CachedStems {
        guard isAvailable, let modelURL else { throw VocalSeparatorError.unavailable }

        if let old = activeTask {
            old.cancel()
            activeTask = nil
            activeTaskKind = nil
            processingSongID = nil
            progressFraction = 0
            jobOwnership.cancelCurrent()
        }

        try Task.checkCancellation()
        guard #available(iOS 18.0, *) else { throw VocalSeparatorError.unavailable }

        let normalizedStart = max(0, fromTime)
        DebugLogger.log(
            "Starting real-time separation for \(songID) from \(normalizedStart)s (no persistent cache)",
            category: .separation
        )

        processingSongID = songID
        activeTaskKind = .foreground
        let jobID = jobOwnership.begin()
        let outputs = Self.separationOutputURLs(
            in: Self.realtimeTempDir,
            songID: songID,
            jobID: jobID
        )
        let vocalsURL = outputs.vocals
        let instrumentsURL = outputs.instruments
        let modelRef = modelURL

        let task = Task<URL, Error>.detached(priority: .utility) {
            let trimmedSource: URL
            let trimmedTemp: URL?
            if normalizedStart > 1.0 {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(jobID.uuidString).rt.trim.m4a")
                try await Self.trim(source: sourceURL, from: normalizedStart, to: tmp)
                trimmedSource = tmp
                trimmedTemp = tmp
            } else {
                trimmedSource = sourceURL
                trimmedTemp = nil
            }
            defer {
                if let trimmedTemp {
                    try? FileManager.default.removeItem(at: trimmedTemp)
                }
            }
            try await Self.runSeparation2(
                modelURL: modelRef,
                jobID: jobID,
                sourceURL: trimmedSource,
                vocalsOutputURL: vocalsURL,
                instrumentsOutputURL: instrumentsURL
            ) { fraction in
                await VocalSeparator.shared.updateProgress(
                    jobID: jobID, songID: songID, fraction: fraction
                )
            }
            return vocalsURL
        }
        activeTask = task
        do {
            _ = try await task.value
            try Task.checkCancellation()
            guard jobOwnership.owns(jobID) else {
                throw VocalSeparatorError.cancelled
            }
            guard FileManager.default.fileExists(atPath: vocalsURL.path),
                  FileManager.default.fileExists(atPath: instrumentsURL.path)
            else {
                throw VocalSeparatorError.unavailable
            }
            try Task.checkCancellation()
            finishJob(jobID: jobID)

            DebugLogger.log(
                "Real-time separation complete for \(songID), offset=\(normalizedStart)",
                category: .separation
            )
            let offset = normalizedStart > 1.0 ? normalizedStart : 0
            return CachedStems(
                vocals: vocalsURL,
                instruments: instrumentsURL,
                startOffset: offset,
                isTemporary: true
            )
        } catch {
            Self.cleanupTmpFiles([vocalsURL, instrumentsURL])
            finishJob(jobID: jobID)
            throw error
        }
    }

    func analyzeInBackground(songID: String, sourceURL: URL) {
        guard isAvailable else { return }
        guard cachedStems(forSongID: songID) == nil else {
            DebugLogger.log(
                "Background analysis skipped — stems already cached for \(songID)",
                category: .ai
            )
            return
        }
        guard processingSongID != songID else { return }

        DebugLogger.log("Starting background analysis for \(songID)", category: .ai)
        isBackgroundAnalyzing = true

        backgroundAnalysisTask?.cancel()
        backgroundAnalysisTask = Task { @MainActor [weak self] in
            do {
                _ = try await self?.separate(
                    forSongID: songID,
                    sourceURL: sourceURL,
                    initiatedByBackground: true
                )
                DebugLogger.log("Background analysis succeeded for \(songID)", category: .ai)
            } catch is CancellationError {
                DebugLogger.log("Background analysis cancelled for \(songID)", category: .ai)
            } catch VocalSeparatorError.cancelled {
                DebugLogger.log("Background analysis cancelled for \(songID)", category: .ai)
            } catch {
                DebugLogger.log("Background analysis failed for \(songID): \(error)", category: .ai)
            }
            self?.isBackgroundAnalyzing = false
        }
    }

    func cancelBackgroundAnalysis() {
        let hadWork = backgroundAnalysisTask != nil
            || activeTaskKind == .background
            || isBackgroundAnalyzing
        backgroundAnalysisTask?.cancel()
        backgroundAnalysisTask = nil
        if activeTaskKind == .background {
            let old = activeTask
            activeTask = nil
            activeTaskKind = nil
            processingSongID = nil
            progressFraction = 0
            jobOwnership.cancelCurrent()
            old?.cancel()
        }
        isBackgroundAnalyzing = false
        if hadWork {
            DebugLogger.log("Background analysis cancelled", category: .ai)
        }
    }

    func cancel() {
        let hadWork = activeTask != nil || processingSongID != nil
        let old = activeTask
        activeTask = nil
        activeTaskKind = nil
        processingSongID = nil
        progressFraction = 0
        jobOwnership.cancelCurrent()
        old?.cancel()
        if hadWork {
            DebugLogger.log("Separation cancelled", category: .separation)
        }
    }

    func clearCache() {
        for directory in AudioCacheStore.cachedSongDirectories() {
            AudioCacheStore.removeStemCache(in: directory)
        }
        DebugLogger.log("Stems cache cleared", category: .cache)
    }

    func cleanupRealtimeTemp() {
        let cutoff = Date()
        realtimeCleanupTask?.cancel()
        realtimeCleanupTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let removed = Self.removeRealtimeTempFiles(createdBefore: cutoff)
            if removed > 0 {
                DebugLogger.log(
                    "Real-time temp files cleaned up: \(removed)",
                    category: .separation
                )
            }
        }
    }

    private nonisolated static func removeRealtimeTempFiles(createdBefore cutoff: Date) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: realtimeTempDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var removed = 0
        for entry in entries {
            guard !Task.isCancelled,
                  let values = try? entry.resourceValues(
                      forKeys: [.contentModificationDateKey]
                  ),
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff
            else { continue }
            do {
                try fm.removeItem(at: entry)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }

    private nonisolated static func expectedDuration(for sourceURL: URL) -> TimeInterval? {
        let duration = AudioCacheStore.audioDuration(at: sourceURL)
        guard duration.isFinite, duration > 1.0 else { return nil }
        return duration
    }

    private func updateProgress(jobID: UUID, songID: String, fraction: Float) {
        if jobOwnership.owns(jobID), processingSongID == songID {
            progressFraction = fraction
        }
    }

    private func finishJob(jobID: UUID) {
        guard jobOwnership.finish(jobID) else { return }
        processingSongID = nil
        progressFraction = 0
        activeTask = nil
        activeTaskKind = nil
    }

    private func publishCompletedFullJob(
        jobID: UUID,
        songID: String,
        staging: (vocals: URL, instruments: URL),
        destinations: (vocals: URL, instruments: URL)
    ) throws {
        guard jobOwnership.owns(jobID) else {
            throw VocalSeparatorError.cancelled
        }
        try Self.publishStemFiles(
            vocalsSource: staging.vocals,
            instrumentsSource: staging.instruments,
            vocalsDestination: destinations.vocals,
            instrumentsDestination: destinations.instruments
        )
        AudioCacheStore.clearMainOffset(for: songID)
        finishJob(jobID: jobID)
        NotificationCenter.default.post(
            name: .vocalSeparatorDidCacheStems,
            object: songID
        )
    }

    private static func trim(source: URL, from startSeconds: TimeInterval, to output: URL)
        async throws
    {
        try? FileManager.default.removeItem(at: output)
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { throw VocalSeparatorError.trimFailed }
        let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let duration = try await asset.load(.duration)
        let safeStartSeconds = min(startSeconds, max(0, duration.seconds - 0.5))
        let safeStart = safeStartSeconds < startSeconds
            ? CMTime(seconds: safeStartSeconds, preferredTimescale: 600) : start
        export.timeRange = CMTimeRange(start: safeStart, end: duration)
        export.outputURL = output
        export.outputFileType = .m4a
        if #available(iOS 18.0, *) {
            try await export.export(to: output, as: .m4a)
        } else {
            await export.export()
            guard export.status == .completed else {
                throw export.error ?? VocalSeparatorError.trimFailed
            }
        }
    }

    @available(iOS 18.0, *)
    private static func runSeparation2(
        modelURL: URL,
        jobID: UUID,
        sourceURL: URL,
        vocalsOutputURL: URL,
        instrumentsOutputURL: URL,
        onProgress: @Sendable @escaping (Float) async -> Void
    ) async throws {
        let separator = try AudioSeparator2(modelURL: modelURL)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeparationJobs", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let tmpVocals = tmpDir.appendingPathComponent("vocals.wav")
        let tmpInstruments = tmpDir.appendingPathComponent("instruments.wav")
        let stems = Stems2(vocals: tmpVocals, accompaniment: tmpInstruments)
        do {
            for try await prog in separator.separate(from: sourceURL, to: stems) {
                try Task.checkCancellation()
                await onProgress(prog.fraction)
            }
        } catch is CancellationError {
            cleanupTmpFiles([tmpVocals, tmpInstruments])
            throw VocalSeparatorError.cancelled
        } catch {
            cleanupTmpFiles([tmpVocals, tmpInstruments])
            throw error
        }
        // Some inference backends finish their AsyncSequence normally after
        // cancellation. Never publish those partial outputs as completed stems.
        do {
            try Task.checkCancellation()
        } catch {
            cleanupTmpFiles([tmpVocals, tmpInstruments])
            throw VocalSeparatorError.cancelled
        }
        let moves: [(URL, URL)] = [
            (tmpVocals, vocalsOutputURL),
            (tmpInstruments, instrumentsOutputURL),
        ]
        for (src, dst) in moves {
            do {
                try Task.checkCancellation()
            } catch {
                cleanupTmpFiles([tmpVocals, tmpInstruments])
                cleanupTmpFiles(moves.map(\.1))
                throw VocalSeparatorError.cancelled
            }
            try? FileManager.default.removeItem(at: dst)
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                try? FileManager.default.removeItem(at: src)
                cleanupTmpFiles([tmpVocals, tmpInstruments])
                cleanupTmpFiles(moves.map(\.1))
                throw error
            }
        }
    }

    private nonisolated static func publishStemFiles(
        vocalsSource: URL,
        instrumentsSource: URL,
        vocalsDestination: URL,
        instrumentsDestination: URL
    ) throws {
        let fileManager = FileManager.default
        let moves = [
            (vocalsSource, vocalsDestination),
            (instrumentsSource, instrumentsDestination),
        ]
        let transactionID = UUID().uuidString
        var backups: [(destination: URL, backup: URL)] = []
        var publishedDestinations: [URL] = []

        do {
            // Move any existing pair aside first. Both replacements are then
            // published as one transaction and the old pair can be restored if
            // either move fails.
            for (_, destination) in moves
            where fileManager.fileExists(atPath: destination.path) {
                let backup = destination.deletingLastPathComponent()
                    .appendingPathComponent(
                        ".\(destination.lastPathComponent).\(transactionID).backup"
                    )
                try fileManager.moveItem(at: destination, to: backup)
                backups.append((destination, backup))
            }

            for (source, destination) in moves {
                try fileManager.moveItem(at: source, to: destination)
                publishedDestinations.append(destination)
            }

            for (_, backup) in backups {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            for destination in publishedDestinations.reversed() {
                try? fileManager.removeItem(at: destination)
            }
            for (destination, backup) in backups.reversed()
            where fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: destination)
                try? fileManager.moveItem(at: backup, to: destination)
            }
            cleanupTmpFiles(moves.map(\.0))
            throw error
        }
    }

    #if DEBUG
        nonisolated static func publishStemFilesForTesting(
            vocalsSource: URL,
            instrumentsSource: URL,
            vocalsDestination: URL,
            instrumentsDestination: URL
        ) throws {
            try publishStemFiles(
                vocalsSource: vocalsSource,
                instrumentsSource: instrumentsSource,
                vocalsDestination: vocalsDestination,
                instrumentsDestination: instrumentsDestination
            )
        }
    #endif

    private nonisolated static func cleanupTmpFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
