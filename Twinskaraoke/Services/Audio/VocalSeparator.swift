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

nonisolated final class TemporaryStemFileLease: @unchecked Sendable {
    let ownedURLs: [URL]

    private let fileManager: FileManager
    private let lock = NSLock()
    private var cleaned = false

    init(urls: [URL], fileManager: FileManager = .default) {
        var seen = Set<URL>()
        ownedURLs = urls.filter { seen.insert($0).inserted }
        self.fileManager = fileManager
    }

    convenience init(
        vocals: URL,
        instruments: URL,
        trimmedSource: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.init(
            urls: [vocals, instruments] + [trimmedSource].compactMap { $0 },
            fileManager: fileManager
        )
    }

    var isCleaned: Bool {
        lock.withLock { cleaned }
    }

    @discardableResult
    func cleanup() -> Bool {
        let shouldClean = lock.withLock {
            guard !cleaned else { return false }
            cleaned = true
            return true
        }
        guard shouldClean else { return false }

        for url in ownedURLs {
            try? fileManager.removeItem(at: url)
        }
        return true
    }

    deinit {
        cleanup()
    }
}

nonisolated struct CachedStems {
    let vocals: URL
    let instruments: URL
    let startOffset: TimeInterval
    let isTemporary: Bool
    let temporaryLease: TemporaryStemFileLease?

    init(
        vocals: URL,
        instruments: URL,
        startOffset: TimeInterval,
        isTemporary: Bool = false,
        temporaryLease: TemporaryStemFileLease? = nil
    ) {
        self.vocals = vocals
        self.instruments = instruments
        self.startOffset = startOffset
        self.isTemporary = isTemporary
        self.temporaryLease = isTemporary ? temporaryLease : nil
    }
}

nonisolated struct SeparationJobGate: Sendable {
    struct Token: Sendable, Equatable {
        let id: UUID
        let songID: String
    }

    private(set) var activeToken: Token?

    mutating func begin(songID: String) -> Token {
        let token = Token(id: UUID(), songID: songID)
        activeToken = token
        return token
    }

    func owns(_ token: Token) -> Bool {
        activeToken == token
    }

    mutating func finish(_ token: Token) -> Bool {
        guard owns(token) else { return false }
        activeToken = nil
        return true
    }

    mutating func finish(
        _ token: Token,
        committing body: () throws -> Void
    ) rethrows -> Bool {
        guard owns(token) else { return false }
        try body()
        activeToken = nil
        return true
    }

    @discardableResult
    mutating func cancel() -> Token? {
        let cancelled = activeToken
        activeToken = nil
        return cancelled
    }
}

nonisolated struct SeparationJobOwnership: Sendable {
    private(set) var activeID: UUID?

    mutating func begin(id: UUID) {
        activeID = id
    }

    func owns(_ id: UUID) -> Bool {
        activeID == id
    }

    mutating func finish(_ id: UUID) -> Bool {
        guard owns(id) else { return false }
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
    private var jobOwnership = SeparationJobGate()
    private var backgroundAnalysisTask: Task<Void, Never>?
    private var backgroundAnalysisGeneration: UInt64 = 0

    private nonisolated static var persistentStagingDir: URL {
        stagingDirectory(named: "VocalSeparationStaging")
    }

    private nonisolated static var realtimeTempDir: URL {
        stagingDirectory(named: "RealtimeStems")
    }

    private init() {
        Self.cleanupAbandonedStagingFiles(in: FileManager.default.temporaryDirectory)
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
        if activeTask != nil { invalidateActiveJob() }
        try Task.checkCancellation()
        guard #available(iOS 18.0, *) else { throw VocalSeparatorError.unavailable }
        DebugLogger.log("Starting full separation for \(songID)", category: .separation)
        let jobToken = jobOwnership.begin(songID: songID)
        processingSongID = songID
        activeTaskKind = initiatedByBackground ? .background : .foreground
        let songFiles = AudioCacheStore.files(for: songID)
        let vocalsURL = songFiles.vocals
        let instrumentsURL = songFiles.instruments
        let staging = Self.stagingURLs(for: jobToken, directory: Self.persistentStagingDir)
        let modelRef = modelURL
        let task = Task<URL, Error>.detached(priority: .utility) {
            do {
                try await Self.runSeparation2(
                    modelURL: modelRef,
                    sourceURL: sourceURL,
                    vocalsOutputURL: staging.vocals,
                    instrumentsOutputURL: staging.instruments
                ) { fraction in
                    await VocalSeparator.shared.updateProgress(job: jobToken, fraction: fraction)
                }
                try Task.checkCancellation()
                try await VocalSeparator.shared.commitPersistentStems(
                    job: jobToken,
                    stagedVocals: staging.vocals,
                    stagedInstruments: staging.instruments,
                    vocalsDestination: vocalsURL,
                    instrumentsDestination: instrumentsURL,
                    cachedSongID: songID
                )
                return vocalsURL
            } catch {
                Self.cleanupTmpFiles([staging.vocals, staging.instruments])
                await VocalSeparator.shared.finishJob(jobToken)
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

        if activeTask != nil { invalidateActiveJob() }

        try Task.checkCancellation()
        guard #available(iOS 18.0, *) else { throw VocalSeparatorError.unavailable }

        let normalizedStart = max(0, fromTime)
        DebugLogger.log(
            "Starting real-time separation for \(songID) from \(normalizedStart)s (no persistent cache)",
            category: .separation
        )

        let jobToken = jobOwnership.begin(songID: songID)
        processingSongID = songID
        activeTaskKind = .foreground
        let staging = Self.stagingURLs(for: jobToken, directory: Self.realtimeTempDir)
        let vocalsURL = staging.vocals
        let instrumentsURL = staging.instruments
        let trimmedTemp = normalizedStart > 1.0
            ? Self.realtimeTempDir.appending(path: "\(jobToken.id.uuidString).trim.m4a")
            : nil
        let temporaryLease = TemporaryStemFileLease(
            vocals: vocalsURL,
            instruments: instrumentsURL,
            trimmedSource: trimmedTemp
        )
        let modelRef = modelURL

        let task = Task<URL, Error>.detached(priority: .utility) {
            do {
                let trimmedSource: URL
                if let trimmedTemp {
                    try await Self.trim(
                        source: sourceURL,
                        from: normalizedStart,
                        to: trimmedTemp
                    )
                    trimmedSource = trimmedTemp
                } else {
                    trimmedSource = sourceURL
                }
                defer {
                    if let trimmedTemp {
                        try? FileManager.default.removeItem(at: trimmedTemp)
                    }
                }
                try await Self.runSeparation2(
                    modelURL: modelRef,
                    sourceURL: trimmedSource,
                    vocalsOutputURL: vocalsURL,
                    instrumentsOutputURL: instrumentsURL
                ) { fraction in
                    await VocalSeparator.shared.updateProgress(job: jobToken, fraction: fraction)
                }
                try Task.checkCancellation()
                guard await VocalSeparator.shared.finishJob(jobToken) else {
                    throw VocalSeparatorError.cancelled
                }
                return vocalsURL
            } catch {
                temporaryLease.cleanup()
                await VocalSeparator.shared.finishJob(jobToken)
                throw error
            }
        }
        activeTask = task
        do {
            _ = try await task.value
        } catch {
            temporaryLease.cleanup()
            throw error
        }

        guard FileManager.default.fileExists(atPath: vocalsURL.path),
              FileManager.default.fileExists(atPath: instrumentsURL.path)
        else {
            temporaryLease.cleanup()
            throw VocalSeparatorError.unavailable
        }

        DebugLogger.log(
            "Real-time separation complete for \(songID), offset=\(normalizedStart)",
            category: .separation
        )
        let offset = normalizedStart > 1.0 ? normalizedStart : 0
        return CachedStems(
            vocals: vocalsURL,
            instruments: instrumentsURL,
            startOffset: offset,
            isTemporary: true,
            temporaryLease: temporaryLease
        )
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
        backgroundAnalysisTask?.cancel()
        backgroundAnalysisGeneration &+= 1
        let generation = backgroundAnalysisGeneration
        isBackgroundAnalyzing = true
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
            guard let self, backgroundAnalysisGeneration == generation else { return }
            backgroundAnalysisTask = nil
            isBackgroundAnalyzing = false
        }
    }

    func cancelBackgroundAnalysis() {
        backgroundAnalysisGeneration &+= 1
        backgroundAnalysisTask?.cancel()
        backgroundAnalysisTask = nil
        if activeTaskKind == .background {
            invalidateActiveJob()
        }
        isBackgroundAnalyzing = false
        DebugLogger.log("Background analysis cancelled", category: .ai)
    }

    func cancel() {
        invalidateActiveJob()
        DebugLogger.log("Separation cancelled", category: .separation)
    }

    func clearCache() {
        for directory in AudioCacheStore.cachedSongDirectories() {
            let songID = directory.lastPathComponent
            removeCachedStems(forSongID: songID)
        }
        DebugLogger.log("Stems cache cleared", category: .cache)
    }

    func cleanupRealtimeTemp() {
        let dir = Self.realtimeTempDir
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) {
            for entry in entries {
                try? FileManager.default.removeItem(at: entry)
            }
        }
        DebugLogger.log("Real-time temp files cleaned up", category: .separation)
    }

    nonisolated static func cleanupAbandonedStagingFiles(
        in temporaryDirectory: URL,
        fileManager: FileManager = .default
    ) {
        for directoryName in ["VocalSeparationStaging", "RealtimeStems"] {
            let directory = temporaryDirectory.appending(
                path: directoryName,
                directoryHint: .isDirectory
            )
            try? fileManager.removeItem(at: directory)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for entry in entries where isLegacyStagingFile(entry.lastPathComponent) {
            try? fileManager.removeItem(at: entry)
        }
    }

    private nonisolated static func expectedDuration(for sourceURL: URL) -> TimeInterval? {
        let duration = AudioCacheStore.audioDuration(at: sourceURL)
        guard duration.isFinite, duration > 1.0 else { return nil }
        return duration
    }

    private func invalidateActiveJob() {
        let task = activeTask
        jobOwnership.cancel()
        activeTask = nil
        activeTaskKind = nil
        processingSongID = nil
        progressFraction = 0
        task?.cancel()
    }

    private func updateProgress(job: SeparationJobGate.Token, fraction: Float) {
        if jobOwnership.owns(job) {
            progressFraction = fraction
        }
    }

    @discardableResult
    private func finishJob(
        _ job: SeparationJobGate.Token,
        cachedSongID: String? = nil
    ) -> Bool {
        guard jobOwnership.finish(job) else { return false }
        publishFinishedJob(cachedSongID: cachedSongID)
        return true
    }

    private func publishFinishedJob(cachedSongID: String?) {
        processingSongID = nil
        progressFraction = 0
        activeTask = nil
        activeTaskKind = nil
        if let cachedSongID {
            NotificationCenter.default.post(
                name: .vocalSeparatorDidCacheStems,
                object: cachedSongID
            )
        }
    }

    private func commitPersistentStems(
        job: SeparationJobGate.Token,
        stagedVocals: URL,
        stagedInstruments: URL,
        vocalsDestination: URL,
        instrumentsDestination: URL,
        cachedSongID: String
    ) throws {
        guard !Task.isCancelled else {
            Self.cleanupTmpFiles([stagedVocals, stagedInstruments])
            throw VocalSeparatorError.cancelled
        }
        let accepted = try jobOwnership.finish(job) {
            try Self.publishStemFiles(
                vocalsSource: stagedVocals,
                instrumentsSource: stagedInstruments,
                vocalsDestination: vocalsDestination,
                instrumentsDestination: instrumentsDestination
            )
            AudioCacheStore.clearMainOffset(for: job.songID)
        }
        guard accepted else {
            Self.cleanupTmpFiles([stagedVocals, stagedInstruments])
            throw VocalSeparatorError.cancelled
        }
        publishFinishedJob(cachedSongID: cachedSongID)
    }

    private nonisolated static func stagingURLs(
        for job: SeparationJobGate.Token,
        directory: URL
    ) -> (vocals: URL, instruments: URL) {
        let basename = job.id.uuidString
        return (
            directory.appendingPathComponent("\(basename).vocals.wav"),
            directory.appendingPathComponent("\(basename).instruments.wav")
        )
    }

    nonisolated static func separationOutputURLs(
        in directory: URL,
        songID: String,
        jobID: UUID
    ) -> (vocals: URL, instruments: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let basename = "\(songID)-\(jobID.uuidString)"
        return (
            directory.appendingPathComponent("\(basename).vocals.wav"),
            directory.appendingPathComponent("\(basename).instruments.wav")
        )
    }

    nonisolated static func cleanupTmpFilesForTesting(_ urls: [URL]) {
        cleanupTmpFiles(urls)
    }

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

    private nonisolated static func stagingDirectory(named name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: name,
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private nonisolated static func isLegacyStagingFile(_ filename: String) -> Bool {
        for suffix in [".vocals.wav", ".instruments.wav"] where filename.hasSuffix(suffix) {
            let token = String(filename.dropLast(suffix.count))
            return UUID(uuidString: token) != nil
        }

        guard filename.hasSuffix(".rt.trim.m4a") else { return false }
        let stem = filename.dropLast(".rt.trim.m4a".count)
        guard let token = stem.split(separator: ".").last else { return false }
        return UUID(uuidString: String(token)) != nil
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
        sourceURL: URL,
        vocalsOutputURL: URL,
        instrumentsOutputURL: URL,
        onProgress: @Sendable @escaping (Float) async -> Void
    ) async throws {
        let separator = try AudioSeparator2(modelURL: modelURL)
        try? FileManager.default.removeItem(at: vocalsOutputURL)
        try? FileManager.default.removeItem(at: instrumentsOutputURL)
        let stems = Stems2(vocals: vocalsOutputURL, accompaniment: instrumentsOutputURL)
        do {
            for try await prog in separator.separate(from: sourceURL, to: stems) {
                try Task.checkCancellation()
                await onProgress(prog.fraction)
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            cleanupTmpFiles([vocalsOutputURL, instrumentsOutputURL])
            throw VocalSeparatorError.cancelled
        } catch {
            cleanupTmpFiles([vocalsOutputURL, instrumentsOutputURL])
            throw error
        }
    }

    private nonisolated static func cleanupTmpFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private nonisolated static func publishStemFiles(
        vocalsSource: URL,
        instrumentsSource: URL,
        vocalsDestination: URL,
        instrumentsDestination: URL
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: vocalsSource.path),
              fm.fileExists(atPath: instrumentsSource.path)
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        let backupID = UUID().uuidString
        let vocalsBackup = vocalsDestination
            .deletingLastPathComponent()
            .appendingPathComponent("\(vocalsDestination.lastPathComponent).backup-\(backupID)")
        let instrumentsBackup = instrumentsDestination
            .deletingLastPathComponent()
            .appendingPathComponent("\(instrumentsDestination.lastPathComponent).backup-\(backupID)")
        var didBackupVocals = false
        var didBackupInstruments = false

        func restoreBackups() {
            try? fm.removeItem(at: vocalsDestination)
            try? fm.removeItem(at: instrumentsDestination)
            if didBackupVocals {
                try? fm.moveItem(at: vocalsBackup, to: vocalsDestination)
            }
            if didBackupInstruments {
                try? fm.moveItem(at: instrumentsBackup, to: instrumentsDestination)
            }
        }

        do {
            if fm.fileExists(atPath: vocalsDestination.path) {
                try fm.moveItem(at: vocalsDestination, to: vocalsBackup)
                didBackupVocals = true
            }
            if fm.fileExists(atPath: instrumentsDestination.path) {
                try fm.moveItem(at: instrumentsDestination, to: instrumentsBackup)
                didBackupInstruments = true
            }
            try fm.moveItem(at: vocalsSource, to: vocalsDestination)
            try fm.moveItem(at: instrumentsSource, to: instrumentsDestination)
            try? fm.removeItem(at: vocalsBackup)
            try? fm.removeItem(at: instrumentsBackup)
        } catch {
            restoreBackups()
            throw error
        }
    }
}
