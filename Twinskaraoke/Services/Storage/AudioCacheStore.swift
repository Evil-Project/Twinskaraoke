import AVFoundation
import Compression
import Foundation

nonisolated final class AudioCacheMainOwnership: @unchecked Sendable {
    struct WriteLease: Equatable, Sendable {
        let id: UUID
        let songID: String
        let generation: UInt64
        let sourceURL: URL
        let directory: URL
        let mainURL: URL
        let sourceMetadataURL: URL
        let mainStagingURL: URL
        let sourceStagingURL: URL
    }

    struct MaintenanceSnapshot: Equatable, Sendable {
        let songID: String
        fileprivate let generation: UInt64
    }

    private struct SongState {
        var generation: UInt64 = 0
        var activeLease: WriteLease?
        var isRemoving = false
    }

    private let condition = NSCondition()
    private let rootDirectory: URL
    private let fileManager: FileManager
    private var states: [String: SongState] = [:]
    private var activeMaintenanceStagingURLs: Set<URL> = []
    private var isClearing = false

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func beginWrite(songID: String, sourceURL: URL) -> WriteLease {
        condition.lock()
        while isClearing || states[songID]?.isRemoving == true {
            condition.wait()
        }

        var state = states[songID] ?? SongState()
        state.generation &+= 1
        let directory = rootDirectory.appendingPathComponent(songID, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let leaseID = UUID()
        let lease = WriteLease(
            id: leaseID,
            songID: songID,
            generation: state.generation,
            sourceURL: sourceURL,
            directory: directory,
            mainURL: directory.appendingPathComponent("main.mp3"),
            sourceMetadataURL: directory.appendingPathComponent("main.source"),
            mainStagingURL: directory.appendingPathComponent("main-\(leaseID.uuidString).mp3.partial"),
            sourceStagingURL: directory.appendingPathComponent("main-\(leaseID.uuidString).source.partial")
        )
        state.activeLease = lease
        states[songID] = state
        condition.unlock()
        return lease
    }

    func owns(_ lease: WriteLease) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !isClearing, let state = states[lease.songID], !state.isRemoving else { return false }
        return state.generation == lease.generation && state.activeLease == lease
    }

    @discardableResult
    func commit(_ lease: WriteLease) throws -> Bool {
        condition.lock()
        guard !isClearing,
              var state = states[lease.songID],
              !state.isRemoving,
              state.generation == lease.generation,
              state.activeLease == lease
        else {
            condition.unlock()
            cleanupStaging(for: lease)
            return false
        }

        var publicationStarted = false
        do {
            try fileManager.createDirectory(at: lease.directory, withIntermediateDirectories: true)
            try Data(lease.sourceURL.absoluteString.utf8).write(
                to: lease.sourceStagingURL,
                options: .atomic
            )
            publicationStarted = true
            try replaceItem(at: lease.mainURL, with: lease.mainStagingURL)
            try replaceItem(at: lease.sourceMetadataURL, with: lease.sourceStagingURL)
            try? fileManager.removeItem(at: lease.mainURL.appendingPathExtension("nkz"))
            state.activeLease = nil
            states[lease.songID] = state
            condition.unlock()
            cleanupStaging(for: lease)
            return true
        } catch {
            if publicationStarted {
                try? fileManager.removeItem(at: lease.mainURL)
                try? fileManager.removeItem(at: lease.sourceMetadataURL)
                try? fileManager.removeItem(at: lease.mainURL.appendingPathExtension("nkz"))
            }
            state.generation &+= 1
            state.activeLease = nil
            states[lease.songID] = state
            condition.unlock()
            cleanupStaging(for: lease)
            throw error
        }
    }

    @discardableResult
    func cancel(_ lease: WriteLease) -> Bool {
        condition.lock()
        var didCancel = false
        if !isClearing,
           var state = states[lease.songID],
           !state.isRemoving,
           state.generation == lease.generation,
           state.activeLease == lease
        {
            state.activeLease = nil
            states[lease.songID] = state
            didCancel = true
        }
        condition.unlock()
        cleanupStaging(for: lease)
        return didCancel
    }

    func beginMaintenance(songID: String) -> MaintenanceSnapshot? {
        condition.lock()
        defer { condition.unlock() }
        guard !isClearing else { return nil }
        let state = states[songID] ?? SongState()
        guard !state.isRemoving, state.activeLease == nil else { return nil }
        states[songID] = state
        return MaintenanceSnapshot(songID: songID, generation: state.generation)
    }

    func isCurrent(_ snapshot: MaintenanceSnapshot) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !isClearing, let state = states[snapshot.songID] else { return false }
        return !state.isRemoving
            && state.activeLease == nil
            && state.generation == snapshot.generation
    }

    @discardableResult
    func registerMaintenanceStaging(
        _ urls: [URL],
        for snapshot: MaintenanceSnapshot
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !isClearing,
              let state = states[snapshot.songID],
              !state.isRemoving,
              state.activeLease == nil,
              state.generation == snapshot.generation
        else { return false }
        activeMaintenanceStagingURLs.formUnion(urls)
        return true
    }

    func unregisterMaintenanceStaging(_ urls: [URL]) {
        condition.lock()
        activeMaintenanceStagingURLs.subtract(urls)
        condition.unlock()
    }

    @discardableResult
    func commitIfUnchanged(
        _ snapshot: MaintenanceSnapshot,
        mutation: () throws -> Void
    ) rethrows -> Bool {
        condition.lock()
        guard !isClearing,
              var state = states[snapshot.songID],
              !state.isRemoving,
              state.activeLease == nil,
              state.generation == snapshot.generation
        else {
            condition.unlock()
            return false
        }

        do {
            try mutation()
            state.generation &+= 1
            states[snapshot.songID] = state
            condition.unlock()
            return true
        } catch {
            state.generation &+= 1
            states[snapshot.songID] = state
            condition.unlock()
            throw error
        }
    }

    @discardableResult
    func removeIfUnchanged(
        _ snapshot: MaintenanceSnapshot,
        removal: () throws -> Void
    ) rethrows -> Bool {
        condition.lock()
        guard !isClearing,
              var state = states[snapshot.songID],
              !state.isRemoving,
              state.activeLease == nil,
              state.generation == snapshot.generation
        else {
            condition.unlock()
            return false
        }
        state.generation &+= 1
        state.isRemoving = true
        states[snapshot.songID] = state
        condition.unlock()

        defer {
            condition.lock()
            if var current = states[snapshot.songID] {
                current.isRemoving = false
                states[snapshot.songID] = current
            }
            condition.broadcast()
            condition.unlock()
        }
        try removal()
        return true
    }

    func invalidateAndRemove(songID: String, removal: () -> Void) {
        condition.lock()
        while isClearing || states[songID]?.isRemoving == true {
            condition.wait()
        }
        var state = states[songID] ?? SongState()
        state.generation &+= 1
        state.activeLease = nil
        state.isRemoving = true
        states[songID] = state
        condition.unlock()

        removal()

        condition.lock()
        if var current = states[songID] {
            current.isRemoving = false
            states[songID] = current
        }
        condition.broadcast()
        condition.unlock()
    }

    func invalidateAllAndRemove(removal: () -> Void) {
        condition.lock()
        while isClearing || states.values.contains(where: \.isRemoving) {
            condition.wait()
        }
        isClearing = true
        for songID in Array(states.keys) {
            var state = states[songID] ?? SongState()
            state.generation &+= 1
            state.activeLease = nil
            states[songID] = state
        }
        condition.unlock()

        removal()

        condition.lock()
        isClearing = false
        condition.broadcast()
        condition.unlock()
    }

    func cleanupPartialFiles() {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent
            let isWriterStaging = fileName.hasSuffix(".partial")
            let isMainMaintenanceStaging =
                (fileName.hasPrefix("main-compress-") || fileName.hasPrefix("main-decompress-"))
                && (fileName.hasSuffix(".staging") || fileName.hasSuffix(".tmp"))
            guard (isWriterStaging || isMainMaintenanceStaging),
                  (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !isActiveStagingURL(fileURL)
            else { continue }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func isActiveStagingURL(_ url: URL) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return states.values.contains { state in
            guard let lease = state.activeLease else { return false }
            return lease.mainStagingURL == url || lease.sourceStagingURL == url
        } || activeMaintenanceStagingURLs.contains(url)
    }

    private func cleanupStaging(for lease: WriteLease) {
        try? fileManager.removeItem(at: lease.mainStagingURL)
        try? fileManager.removeItem(at: lease.sourceStagingURL)
    }

    private func replaceItem(at destination: URL, with stagedURL: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: stagedURL, to: destination)
    }
}

nonisolated enum AudioCacheStore {
    typealias MainWriteLease = AudioCacheMainOwnership.WriteLease

    struct SongFiles {
        let directory: URL
        let main: URL
        let mainPartial: URL
        let mainSource: URL
        let vocals: URL
        let instruments: URL
        let offset: URL
    }

    // FileManager.default is thread-safe; Algorithm is an immutable enum value.
    private nonisolated(unsafe) static let fm = FileManager.default
    private static let compressionExtension = "nkz"
    private nonisolated(unsafe) static let compressionAlgorithm: Algorithm = .lzfse
    private static let chunkSize = 64 * 1024
    private static let maximumPlayableFileSize: Int64 = 256 * 1024 * 1024
    private static let cacheDirectory: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
    private static let mainOwnership = AudioCacheMainOwnership(
        rootDirectory: cacheDirectory,
        fileManager: fm
    )

    static func files(for songID: String) -> SongFiles {
        let directory = ensureSongDirectory(for: songID)
        return SongFiles(
            directory: directory,
            main: directory.appendingPathComponent("main.mp3"),
            mainPartial: directory.appendingPathComponent("main.mp3.partial"),
            mainSource: directory.appendingPathComponent("main.source"),
            vocals: directory.appendingPathComponent("vocals.wav"),
            instruments: directory.appendingPathComponent("instruments.wav"),
            offset: directory.appendingPathComponent("offset")
        )
    }

    static func ensureSongDirectory(for songID: String) -> URL {
        let directory = cacheDirectory.appendingPathComponent(songID, isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func beginMainWrite(songID: String, sourceURL: URL) -> MainWriteLease {
        mainOwnership.beginWrite(songID: songID, sourceURL: sourceURL)
    }

    static func ownsMainWrite(_ lease: MainWriteLease) -> Bool {
        mainOwnership.owns(lease)
    }

    @discardableResult
    static func commitMainWrite(_ lease: MainWriteLease) throws -> Bool {
        try mainOwnership.commit(lease)
    }

    static func cancelMainWrite(_ lease: MainWriteLease) {
        mainOwnership.cancel(lease)
    }

    static func playableMainURL(for songID: String, expectedRemoteURL: URL? = nil, expectedDuration: TimeInterval? = nil) -> URL? {
        validatedMainURL(
            for: songID,
            expectedRemoteURL: expectedRemoteURL,
            expectedDuration: expectedDuration,
            allowDecompression: true
        )
    }

    /// Like `playableMainURL`, but never decompresses: returns nil when only the
    /// compressed cache exists, so callers on the main thread can defer that
    /// work to a background path instead.
    static func immediatelyPlayableMainURL(
        for songID: String,
        expectedRemoteURL: URL? = nil,
        expectedDuration: TimeInterval? = nil
    ) -> URL? {
        validatedMainURL(
            for: songID,
            expectedRemoteURL: expectedRemoteURL,
            expectedDuration: expectedDuration,
            allowDecompression: false
        )
    }

    static func playableStems(
        for songID: String,
        startOffset: TimeInterval,
        expectedDuration: TimeInterval? = nil
    ) -> CachedStems? {
        let songFiles = files(for: songID)
        guard let vocals = playableURL(for: songFiles.vocals),
              let instruments = playableURL(for: songFiles.instruments)
        else {
            return nil
        }
        guard validateStemPair(
            vocals: vocals,
            instruments: instruments,
            startOffset: startOffset,
            expectedDuration: expectedDuration
        )
        else {
            DebugLogger.log("Removing invalid stem cache for \(songID)", category: .cache)
            removeStemCache(for: songID)
            return nil
        }
        return CachedStems(vocals: vocals, instruments: instruments, startOffset: startOffset)
    }

    static func hasCachedMainAudio(for songID: String, expectedRemoteURL: URL? = nil, expectedDuration: TimeInterval? = nil) -> Bool {
        playableMainURL(
            for: songID,
            expectedRemoteURL: expectedRemoteURL,
            expectedDuration: expectedDuration
        ) != nil
    }

    static func hasCachedStems(for songID: String) -> Bool {
        playableStems(for: songID, startOffset: readStartOffset(for: songID)) != nil
    }

    static func compressedURL(for playableURL: URL) -> URL {
        playableURL.appendingPathExtension(compressionExtension)
    }

    static func mainAudioURL(for songID: String, sourceURL: URL) -> URL {
        ensureSongDirectory(for: songID)
            .appendingPathComponent("main.\(audioExtension(for: sourceURL))")
    }

    static func mainPartialAudioURL(for songID: String, sourceURL: URL) -> URL {
        ensureSongDirectory(for: songID)
            .appendingPathComponent("main.partial.\(audioExtension(for: sourceURL))")
    }

    static func shouldRemovePartialFile(
        named fileName: String,
        modifiedAt: Date?,
        createdBefore cutoff: Date
    ) -> Bool {
        guard fileName.contains(".partial"),
              let modifiedAt,
              modifiedAt < cutoff
        else { return false }
        return true
    }

    static func shouldCompressPlayableFile(at url: URL) -> Bool {
        let fileName = url.lastPathComponent.lowercased()
        guard !fileName.hasSuffix(".\(compressionExtension)") else { return false }
        switch url.pathExtension.lowercased() {
        case "wav", "aif", "aiff", "caf":
            return true
        default:
            return false
        }
    }

    static func commitMainAudioFile(at stagedURL: URL, to finalURL: URL, for songID: String) throws {
        guard fm.fileExists(atPath: stagedURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = ensureSongDirectory(for: songID)
        try replaceItem(at: finalURL, with: stagedURL)
        removeMainAudioVariants(in: directory, preserving: finalURL)
    }

    static func cachedSongDirectories() -> [URL] {
        guard
            let entries = try? fm.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    static func removeSongCache(for songID: String) {
        let directory = cacheDirectory.appendingPathComponent(songID, isDirectory: true)
        // Explicit recovery wins over in-flight writers. Validation and other
        // opportunistic maintenance use generation-conditional removal below.
        mainOwnership.invalidateAndRemove(songID: songID) {
            try? fm.removeItem(at: directory)
        }
    }

    static func clearAllCache() {
        mainOwnership.invalidateAllAndRemove {
            guard let entries = try? fm.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            ) else { return }
            for url in entries {
                try? fm.removeItem(at: url)
            }
        }
    }

    static func removeStemCache(for songID: String) {
        let songFiles = files(for: songID)
        let urls = [
            songFiles.vocals,
            songFiles.instruments,
            compressedURL(for: songFiles.vocals),
            compressedURL(for: songFiles.instruments),
            songFiles.offset,
        ]
        for url in urls {
            try? fm.removeItem(at: url)
        }
    }

    static func clearMainOffset(for songID: String) {
        try? fm.removeItem(at: files(for: songID).offset)
    }

    static func writeStartOffset(_ offset: TimeInterval, for songID: String) {
        let data = "\(offset)".data(using: .utf8)
        fm.createFile(atPath: files(for: songID).offset.path, contents: data)
    }

    static func readStartOffset(for songID: String) -> TimeInterval {
        guard let data = try? Data(contentsOf: files(for: songID).offset),
              let str = String(data: data, encoding: .utf8),
              let value = Double(str.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return 0
        }
        return value
    }

    static func cleanupLegacyArtifacts() {
        cleanupPartialFiles()
        guard
            let entries = try? fm.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if !isDirectory {
                try? fm.removeItem(at: entry)
            }
        }
    }

    static func cleanupPartialFiles() {
        mainOwnership.cleanupPartialFiles()
    }

    static func compressIdleAssets(excluding songIDs: Set<String>) {
        for directory in cachedSongDirectories() where !songIDs.contains(directory.lastPathComponent) {
            if Task.isCancelled { break }
            let songID = directory.lastPathComponent
            compressAssets(for: songID)
        }
    }

    static func compressAssets(for songID: String) {
        let songFiles = files(for: songID)
        compressMainFileIfNeeded(for: songID, files: songFiles)
        compressPlayableFileIfNeeded(at: songFiles.vocals)
        compressPlayableFileIfNeeded(at: songFiles.instruments)
    }

    static func touch(_ url: URL) {
        guard isCacheURL(url) else { return }
        let now = Date()
        try? fm.setAttributes([.modificationDate: now], ofItemAtPath: url.path)

        let rootPath = cacheDirectory.path
        let songDirectory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        if isCacheURL(songDirectory), songDirectory.path != rootPath {
            try? fm.setAttributes([.modificationDate: now], ofItemAtPath: songDirectory.path)
        }
    }

    private static func isCacheURL(_ url: URL) -> Bool {
        let rootPath = cacheDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func hasCachedPlayableFile(at url: URL) -> Bool {
        fm.fileExists(atPath: url.path) || fm.fileExists(atPath: compressedURL(for: url).path)
    }

    private static func audioExtension(for sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.lowercased()
        return ext.isEmpty ? "mp3" : ext
    }

    private static func removeMainAudioVariants(in directory: URL, preserving finalURL: URL) {
        for ext in ["mp3", "m4a", "aac", "wav", "caf", "aif", "aiff"] {
            let url = directory.appendingPathComponent("main.\(ext)")
            if url != finalURL {
                try? fm.removeItem(at: url)
                try? fm.removeItem(at: compressedURL(for: url))
            }
            try? fm.removeItem(at: directory.appendingPathComponent("main.partial.\(ext)"))
        }
    }

    private static func validatedMainURL(
        for songID: String,
        expectedRemoteURL: URL?,
        expectedDuration: TimeInterval?,
        allowDecompression: Bool
    ) -> URL? {
        for _ in 0 ..< 3 {
            guard let snapshot = mainOwnership.beginMaintenance(songID: songID) else { return nil }
            let songFiles = files(for: songID)
            guard hasCachedPlayableFile(at: songFiles.main) else { return nil }

            if let expectedRemoteURL {
                guard let cachedSource = readMainSourceURL(at: songFiles.mainSource) else {
                    if discardMainCache(
                        snapshot,
                        files: songFiles,
                        message: "Discarding legacy audio cache without source metadata for \(songID)"
                    ) { return nil }
                    continue
                }
                guard cachedSource == expectedRemoteURL.absoluteString else {
                    if discardMainCache(
                        snapshot,
                        files: songFiles,
                        message: "Discarding stale audio cache for \(songID) due to source mismatch"
                    ) { return nil }
                    continue
                }
            }

            let actualURL: URL
            if fm.fileExists(atPath: songFiles.main.path) {
                guard isValidAudioFile(at: songFiles.main) else {
                    if discardMainCache(
                        snapshot,
                        files: songFiles,
                        message: "Discarding broken main audio cache for \(songID)"
                    ) { return nil }
                    continue
                }
                actualURL = songFiles.main
            } else {
                guard allowDecompression,
                      decompressMainFileIfNeeded(snapshot: snapshot, files: songFiles)
                else { return nil }
                continue
            }

            if let expectedDuration, expectedDuration > 0 {
                let actualDuration = getAudioDuration(at: actualURL)
                guard actualDuration.isFinite, actualDuration > 1.0 else {
                    if discardMainCache(
                        snapshot,
                        files: songFiles,
                        message: "Discarding audio cache for \(songID) because duration could not be measured"
                    ) { return nil }
                    continue
                }
                let tolerance: TimeInterval = 2.0
                guard abs(actualDuration - expectedDuration) <= tolerance else {
                    if discardMainCache(
                        snapshot,
                        files: songFiles,
                        message: "Discarding audio cache for \(songID) due to duration mismatch: expected \(expectedDuration)s, got \(actualDuration)s"
                    ) { return nil }
                    continue
                }
            }

            guard mainOwnership.isCurrent(snapshot) else { continue }
            touch(actualURL)
            return actualURL
        }
        return nil
    }

    private static func discardMainCache(
        _ snapshot: AudioCacheMainOwnership.MaintenanceSnapshot,
        files songFiles: SongFiles,
        message: String
    ) -> Bool {
        DebugLogger.log(message, category: .cache)
        return mainOwnership.removeIfUnchanged(snapshot) {
            try? fm.removeItem(at: songFiles.directory)
        }
    }

    private static func readMainSourceURL(at sourceURL: URL) -> String? {
        guard let data = try? Data(contentsOf: sourceURL),
              let rawValue = String(data: data, encoding: .utf8)
        else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static let minimumPlayableFileSize = 4096

    private static func playableURL(for url: URL) -> URL? {
        if fm.fileExists(atPath: url.path) {
            if !isValidAudioFile(at: url) {
                DebugLogger.log("Removing broken cache file: \(url.lastPathComponent)", category: .cache)
                try? fm.removeItem(at: url)
                try? fm.removeItem(at: compressedURL(for: url))
                return nil
            }
            touch(url)
            return url
        }
        let compressed = compressedURL(for: url)
        guard fm.fileExists(atPath: compressed.path) else { return nil }
        do {
            try decompressFileIfNeeded(from: compressed, to: url)
            if !isValidAudioFile(at: url) {
                DebugLogger.log("Removing broken compressed cache: \(url.lastPathComponent)", category: .cache)
                try? fm.removeItem(at: url)
                try? fm.removeItem(at: compressed)
                return nil
            }
            touch(url)
            touch(compressed)
            return url
        } catch {
            DebugLogger.log("Audio cache decompress failed for \(url.lastPathComponent): \(error)", category: .cache)
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: compressed)
            return nil
        }
    }

    private static func isValidAudioFile(at url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= minimumPlayableFileSize else { return false }
        return AVEnginePlayback.hasValidAudioHeader(at: url)
    }

    static func audioDuration(at url: URL) -> TimeInterval {
        if let file = try? AVAudioFile(forReading: url) {
            let sampleRate = file.fileFormat.sampleRate
            if sampleRate > 0 {
                let duration = Double(file.length) / sampleRate
                if duration.isFinite, duration > 0 { return duration }
            }
        }
        return 0
    }

    static func acceptsAudioResponse(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        guard (200 ... 299).contains(http.statusCode) else { return false }
        if http.expectedContentLength > maximumPlayableFileSize {
            return false
        }
        guard let mimeType = http.mimeType?.lowercased(), !mimeType.isEmpty else { return true }
        return !mimeType.hasPrefix("text/")
            && mimeType != "application/json"
            && !mimeType.hasSuffix("+json")
    }

    static func isPlayableAudioFile(at url: URL) -> Bool {
        isValidAudioFile(at: url)
    }

    private static func getAudioDuration(at url: URL) -> TimeInterval {
        audioDuration(at: url)
    }

    private static func validateStemPair(
        vocals: URL,
        instruments: URL,
        startOffset: TimeInterval,
        expectedDuration: TimeInterval?
    ) -> Bool {
        guard startOffset.isFinite, startOffset >= 0 else { return false }
        let vocalsDuration = audioDuration(at: vocals)
        let instrumentsDuration = audioDuration(at: instruments)
        guard vocalsDuration.isFinite, instrumentsDuration.isFinite,
              vocalsDuration > 1.0, instrumentsDuration > 1.0
        else {
            return false
        }
        let pairTolerance = max(2.0, min(vocalsDuration, instrumentsDuration) * 0.02)
        guard abs(vocalsDuration - instrumentsDuration) <= pairTolerance else {
            return false
        }
        guard let expectedDuration, expectedDuration.isFinite, expectedDuration > 1.0 else {
            return true
        }
        let expectedStemDuration = max(0, expectedDuration - startOffset)
        guard expectedStemDuration > 1.0 else { return true }
        let expectedTolerance = max(4.0, expectedDuration * 0.05)
        return vocalsDuration + expectedTolerance >= expectedStemDuration
            && instrumentsDuration + expectedTolerance >= expectedStemDuration
    }

    private static func compressMainFileIfNeeded(for songID: String, files songFiles: SongFiles) {
        guard let snapshot = mainOwnership.beginMaintenance(songID: songID),
              fm.fileExists(atPath: songFiles.main.path)
        else { return }
        let compressed = compressedURL(for: songFiles.main)

        if compressedIsCurrent(for: songFiles.main, compressedURL: compressed) {
            if canDecompressFile(compressed) {
                _ = mainOwnership.commitIfUnchanged(snapshot) {
                    try? fm.removeItem(at: songFiles.main)
                }
            } else {
                DebugLogger.log("Removing invalid compressed cache: \(compressed.lastPathComponent)", category: .cache)
                _ = mainOwnership.commitIfUnchanged(snapshot) {
                    try? fm.removeItem(at: compressed)
                }
            }
            return
        }

        let stagingURL = songFiles.directory.appendingPathComponent(
            "main-compress-\(UUID().uuidString).nkz.staging"
        )
        let stagingURLs = [stagingURL, stagingURL.appendingPathExtension("tmp")]
        guard mainOwnership.registerMaintenanceStaging(stagingURLs, for: snapshot) else { return }
        defer {
            mainOwnership.unregisterMaintenanceStaging(stagingURLs)
            for url in stagingURLs {
                try? fm.removeItem(at: url)
            }
        }

        do {
            try compressFile(from: songFiles.main, to: stagingURL)
            guard canDecompressFile(stagingURL) else {
                DebugLogger.log("Compression produced invalid file: \(songFiles.main.lastPathComponent)", category: .cache)
                return
            }
            _ = try mainOwnership.commitIfUnchanged(snapshot) {
                try replaceItem(at: compressed, with: stagingURL)
                try? fm.removeItem(at: songFiles.main)
            }
        } catch {
            DebugLogger.log("Audio cache compress failed for \(songFiles.main.lastPathComponent): \(error)", category: .cache)
        }
    }

    private static func decompressMainFileIfNeeded(
        snapshot: AudioCacheMainOwnership.MaintenanceSnapshot,
        files songFiles: SongFiles
    ) -> Bool {
        let compressed = compressedURL(for: songFiles.main)
        guard fm.fileExists(atPath: compressed.path) else { return false }
        let stagingURL = songFiles.directory.appendingPathComponent(
            "main-decompress-\(UUID().uuidString).mp3.staging"
        )
        let stagingURLs = [stagingURL, stagingURL.appendingPathExtension("tmp")]
        guard mainOwnership.registerMaintenanceStaging(stagingURLs, for: snapshot) else { return false }
        defer {
            mainOwnership.unregisterMaintenanceStaging(stagingURLs)
            for url in stagingURLs {
                try? fm.removeItem(at: url)
            }
        }

        do {
            try decompressFileIfNeeded(from: compressed, to: stagingURL)
            guard isValidAudioFile(at: stagingURL) else {
                DebugLogger.log("Removing broken compressed cache: \(compressed.lastPathComponent)", category: .cache)
                _ = mainOwnership.commitIfUnchanged(snapshot) {
                    try? fm.removeItem(at: compressed)
                }
                return false
            }
            return try mainOwnership.commitIfUnchanged(snapshot) {
                try replaceItem(at: songFiles.main, with: stagingURL)
            }
        } catch {
            DebugLogger.log("Audio cache decompress failed for \(songFiles.main.lastPathComponent): \(error)", category: .cache)
            _ = mainOwnership.commitIfUnchanged(snapshot) {
                try? fm.removeItem(at: compressed)
            }
            return false
        }
    }

    private static func compressPlayableFileIfNeeded(at url: URL) {
        guard fm.fileExists(atPath: url.path) else { return }
        let compressed = compressedURL(for: url)

        if compressedIsCurrent(for: url, compressedURL: compressed) {
            if canDecompressFile(compressed) {
                try? fm.removeItem(at: url)
            } else {
                DebugLogger.log("Removing invalid compressed cache: \(compressed.lastPathComponent)", category: .cache)
                try? fm.removeItem(at: compressed)
            }
            return
        }

        do {
            try compressFile(from: url, to: compressed)
            if canDecompressFile(compressed) {
                try? fm.removeItem(at: url)
            } else {
                DebugLogger.log("Compression produced invalid file: \(compressed.lastPathComponent)", category: .cache)
                try? fm.removeItem(at: compressed)
            }
        } catch {
            DebugLogger.log("Audio cache compress failed for \(url.lastPathComponent): \(error)", category: .cache)
            try? fm.removeItem(at: compressed)
        }
    }

    private static func compressedIsCurrent(for sourceURL: URL, compressedURL: URL) -> Bool {
        guard fm.fileExists(atPath: compressedURL.path) else { return false }
        guard let sourceDate = modificationDate(for: sourceURL),
              let compressedDate = modificationDate(for: compressedURL)
        else {
            return true
        }
        return compressedDate >= sourceDate
    }

    private static func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func replaceItem(at destinationURL: URL, with stagedURL: URL) throws {
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.moveItem(at: stagedURL, to: destinationURL)
    }

    private static func compressFile(from sourceURL: URL, to destinationURL: URL) throws {
        let tempURL = destinationURL.appendingPathExtension("tmp")
        try? fm.removeItem(at: tempURL)
        fm.createFile(atPath: tempURL.path, contents: nil)

        do {
            let reader = try FileHandle(forReadingFrom: sourceURL)
            let writer = try FileHandle(forWritingTo: tempURL)
            defer {
                try? reader.close()
                try? writer.close()
            }

            let filter = try OutputFilter(.compress, using: compressionAlgorithm) { data in
                guard let data else { return }
                try writer.write(contentsOf: data)
            }

            while true {
                let chunk = try reader.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                try filter.write(chunk)
            }
            try filter.finalize()

            try? fm.removeItem(at: destinationURL)
            try fm.moveItem(at: tempURL, to: destinationURL)
        } catch {
            try? fm.removeItem(at: tempURL)
            throw error
        }
    }

    private static func decompressFileIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
        let tempURL = destinationURL.appendingPathExtension("tmp")
        try? fm.removeItem(at: tempURL)
        fm.createFile(atPath: tempURL.path, contents: nil)

        do {
            let reader = try FileHandle(forReadingFrom: sourceURL)
            let writer = try FileHandle(forWritingTo: tempURL)
            defer {
                try? reader.close()
                try? writer.close()
            }

            let filter = try InputFilter<Data>(.decompress, using: compressionAlgorithm) { requestedCount in
                try reader.read(upToCount: requestedCount)
            }

            while let chunk = try filter.readData(ofLength: chunkSize), !chunk.isEmpty {
                try writer.write(contentsOf: chunk)
            }

            try? fm.removeItem(at: destinationURL)
            try fm.moveItem(at: tempURL, to: destinationURL)
        } catch {
            try? fm.removeItem(at: tempURL)
            throw error
        }
    }

    private static func canDecompressFile(_ compressedURL: URL) -> Bool {
        guard fm.fileExists(atPath: compressedURL.path) else { return false }
        do {
            let reader = try FileHandle(forReadingFrom: compressedURL)
            defer { try? reader.close() }
            let filter = try InputFilter<Data>(.decompress, using: compressionAlgorithm) { requestedCount in
                try reader.read(upToCount: requestedCount)
            }
            _ = try filter.readData(ofLength: chunkSize)
            return true
        } catch {
            return false
        }
    }
}
