import AVFoundation
import Compression
import Foundation

nonisolated enum AudioCacheStore {
    struct SongFiles {
        let directory: URL
        let mainSource: URL
        let vocals: URL
        let instruments: URL
        let offset: URL
    }

    // FileManager.default is thread-safe; Algorithm is an immutable enum value.
    private nonisolated(unsafe) static let fm = FileManager.default
    private static let compressionLock = NSLock()
    private static let compressionExtension = "nkz"
    private nonisolated(unsafe) static let compressionAlgorithm: Algorithm = .lzfse
    private static let chunkSize = 64 * 1024
    private static let maximumPlayableFileSize: Int64 = 256 * 1024 * 1024
    // Track-start paths probe the same cached file several times per song
    // (header validation + duration), each opening a fresh AVAudioFile. Memoize
    // per (path, modificationDate); `touch` bumps the modification date, so
    // entries invalidate conservatively whenever the file changes.
    private static let probeMemoLock = NSLock()
    private static let probeMemoLimit = 256
    private nonisolated(unsafe) static var durationMemo: [String: (modified: Date, duration: TimeInterval)] = [:]
    private nonisolated(unsafe) static var validityMemo: [String: (modified: Date, valid: Bool)] = [:]
    static let supportedMainAudioExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "m4b", "mp3", "mp4", "wav",
    ]
    private static let cacheDirectory: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func files(for songID: String) -> SongFiles {
        songFiles(
            in: cacheDirectory.appendingPathComponent(
                SongStorageKey.component(for: songID),
                isDirectory: true
            )
        )
    }

    static func mainAudioURL(for songID: String, sourceURL: URL) -> URL {
        files(for: songID).directory.appendingPathComponent(
            "main.\(mainAudioExtension(for: sourceURL))"
        )
    }

    static func mainPartialAudioURL(for songID: String, sourceURL: URL) -> URL {
        files(for: songID).directory.appendingPathComponent(
            "main.partial.\(mainAudioExtension(for: sourceURL))"
        )
    }

    static func removeMainAudioFiles(for songID: String, excluding preservedURL: URL? = nil) {
        let directory = files(for: songID).directory
        let preservedURL = preservedURL?.standardizedFileURL
        for url in cachedMainAudioURLs(in: directory) {
            guard url.standardizedFileURL != preservedURL else { continue }
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: compressedURL(for: url))
        }
    }

    static func commitMainAudioFile(at stagedURL: URL, to finalURL: URL, for songID: String) throws {
        if fm.fileExists(atPath: finalURL.path) {
            _ = try fm.replaceItemAt(finalURL, withItemAt: stagedURL)
        } else {
            try fm.moveItem(at: stagedURL, to: finalURL)
        }

        // A newly committed uncompressed file supersedes any compressed copy
        // and alternate legacy-extension variants.
        try? fm.removeItem(at: compressedURL(for: finalURL))
        removeMainAudioFiles(for: songID, excluding: finalURL)
        CacheManager.noteMusicCacheCommit()
    }

    private static func songFiles(in directory: URL) -> SongFiles {
        return SongFiles(
            directory: directory,
            mainSource: directory.appendingPathComponent("main.source"),
            vocals: directory.appendingPathComponent("vocals.wav"),
            instruments: directory.appendingPathComponent("instruments.wav"),
            offset: directory.appendingPathComponent("offset")
        )
    }

    static func ensureSongDirectory(for songID: String) -> URL {
        let directory = cacheDirectory.appendingPathComponent(
            SongStorageKey.component(for: songID),
            isDirectory: true
        )
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func playableMainURL(for songID: String, expectedRemoteURL: URL? = nil, expectedDuration: TimeInterval? = nil) -> URL? {
        for candidate in mainAudioCandidates(
            songID: songID,
            expectedRemoteURL: expectedRemoteURL
        ) {
            guard let playable = playableURL(for: candidate) else { continue }
            guard validateMainSource(for: songID, expectedRemoteURL: expectedRemoteURL) else {
                return nil
            }
            if let expectedDuration, expectedDuration.isFinite, expectedDuration > 1.0 {
                let actualDuration = audioDuration(at: playable)
                guard durationAppearsComplete(
                    actualDuration: actualDuration,
                    expectedDuration: expectedDuration
                ) else {
                    DebugLogger.log(
                        "Discarding audio cache for \(songID) due to duration mismatch: expected \(expectedDuration)s, got \(actualDuration)s",
                        category: .cache
                    )
                    removeSongCache(for: songID)
                    return nil
                }
            }
            return playable
        }
        return nil
    }

    /// Like `playableMainURL`, but never decompresses: returns nil when only the
    /// compressed cache exists, so callers on the main thread can defer that
    /// work to a background path instead.
    static func immediatelyPlayableMainURL(
        for songID: String,
        expectedRemoteURL: URL? = nil,
        expectedDuration: TimeInterval? = nil
    ) -> URL? {
        for candidate in mainAudioCandidates(
            songID: songID,
            expectedRemoteURL: expectedRemoteURL
        ) {
            guard fm.fileExists(atPath: candidate.path), isValidAudioFile(at: candidate) else {
                continue
            }
            guard validateMainSource(for: songID, expectedRemoteURL: expectedRemoteURL) else {
                return nil
            }
            if let expectedDuration, expectedDuration.isFinite, expectedDuration > 1.0 {
                let actualDuration = audioDuration(at: candidate)
                guard durationAppearsComplete(
                    actualDuration: actualDuration,
                    expectedDuration: expectedDuration
                ) else {
                    DebugLogger.log(
                        "Discarding immediate audio cache for \(songID) due to duration mismatch: expected \(expectedDuration)s, got \(actualDuration)s",
                        category: .cache
                    )
                    removeSongCache(for: songID)
                    return nil
                }
            }
            touch(candidate)
            return candidate
        }
        return nil
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

    /// Like `playableStems`, but never decompresses: returns nil when only the
    /// compressed cache exists, so callers on the main thread can defer that
    /// work to a background path instead.
    static func immediatelyPlayableStems(
        for songID: String,
        startOffset: TimeInterval,
        expectedDuration: TimeInterval? = nil
    ) -> CachedStems? {
        let songFiles = files(for: songID)
        let vocals = songFiles.vocals
        let instruments = songFiles.instruments
        guard fm.fileExists(atPath: vocals.path), isValidAudioFile(at: vocals),
              fm.fileExists(atPath: instruments.path), isValidAudioFile(at: instruments)
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
        touch(vocals)
        touch(instruments)
        return CachedStems(vocals: vocals, instruments: instruments, startOffset: startOffset)
    }

    static func compressedURL(for playableURL: URL) -> URL {
        playableURL.appendingPathExtension(compressionExtension)
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
        try? fm.removeItem(at: files(for: songID).directory)
        // The music tree changed outside an enforcement pass; tell the
        // debounced enforcer so it re-measures instead of reusing a stale size.
        CacheManager.noteMusicCacheCommit()
    }

    static func removeStemCache(for songID: String) {
        removeStemCache(in: files(for: songID).directory)
    }

    static func removeStemCache(in directory: URL) {
        let songFiles = songFiles(in: directory)
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

    static func writeMainSourceURL(_ remoteURL: URL?, for songID: String) {
        if remoteURL != nil {
            _ = ensureSongDirectory(for: songID)
        }
        let sourceURL = files(for: songID).mainSource
        guard let remoteURL else {
            try? fm.removeItem(at: sourceURL)
            return
        }
        let data = remoteURL.absoluteString.data(using: .utf8)
        try? fm.removeItem(at: sourceURL)
        fm.createFile(atPath: sourceURL.path, contents: data)
    }

    static func writeStartOffset(_ offset: TimeInterval, for songID: String) {
        _ = ensureSongDirectory(for: songID)
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

    static func cleanupLegacyArtifacts(createdBefore cutoff: Date) {
        cleanupPartialFiles(createdBefore: cutoff)
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

    static func cleanupPartialFiles(createdBefore cutoff: Date) {
        guard
            let enumerator = fm.enumerator(
                at: cacheDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                      forKeys: [.isRegularFileKey, .contentModificationDateKey]
                  ),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  shouldRemovePartialFile(
                      named: fileURL.lastPathComponent,
                      modifiedAt: modifiedAt,
                      createdBefore: cutoff
                  )
            else { continue }
            try? fm.removeItem(at: fileURL)
        }
    }

    static func shouldRemovePartialFile(
        named name: String,
        modifiedAt: Date,
        createdBefore cutoff: Date
    ) -> Bool {
        (name.hasSuffix(".partial") || name.contains(".partial.")) && modifiedAt < cutoff
    }

    static func mainAudioExtension(for sourceURL: URL) -> String {
        let pathExtension = sourceURL.pathExtension.lowercased()
        return supportedMainAudioExtensions.contains(pathExtension) ? pathExtension : "mp3"
    }

    private static func mainAudioCandidates(songID: String, expectedRemoteURL: URL?) -> [URL] {
        if let expectedRemoteURL {
            // The container extension is part of Core Audio's file-type
            // selection. Do not reuse a legacy `main.mp3` that contains M4A
            // bytes from the same source URL.
            return [mainAudioURL(for: songID, sourceURL: expectedRemoteURL)]
        }
        return cachedMainAudioURLs(in: files(for: songID).directory)
    }

    private static func cachedMainAudioURLs(in directory: URL) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
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
                    && supportedMainAudioExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func compressIdleAssets(excluding songIDs: Set<String>) {
        guard compressionLock.try() else { return }
        defer { compressionLock.unlock() }

        let excludedStorageKeys = SongStorageKey.components(for: songIDs)
        for directory in cachedSongDirectories()
            where !excludedStorageKeys.contains(directory.lastPathComponent)
        {
            if Task.isCancelled { break }
            compressAssets(in: directory)
        }
    }

    static func compressAssets(for songID: String) {
        // Match compressIdleAssets: the wav deletes below must hold the same
        // lock playableURL try-locks before handing a file out.
        guard compressionLock.try() else { return }
        defer { compressionLock.unlock() }
        compressAssets(in: files(for: songID).directory)
    }

    private static func compressAssets(in directory: URL) {
        let songFiles = songFiles(in: directory)
        guard !Task.isCancelled else { return }
        compressPlayableFileIfNeeded(at: songFiles.vocals)
        guard !Task.isCancelled else { return }
        compressPlayableFileIfNeeded(at: songFiles.instruments)
    }

    static func shouldCompressPlayableFile(at url: URL) -> Bool {
        url.pathExtension.lowercased() == "wav"
    }

    static func touch(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        let standardizedCacheDirectory = cacheDirectory.standardizedFileURL
        let cachePathPrefix = standardizedCacheDirectory.path + "/"
        // Lyrics cache files live outside AudioCache but share the same
        // access-date LRU bookkeeping.
        let standardizedLyricsDirectory = LyricsCacheStore.cacheDirectory.standardizedFileURL
        let lyricsPathPrefix = standardizedLyricsDirectory.path + "/"
        guard standardizedURL.path.hasPrefix(cachePathPrefix)
            || standardizedURL.path.hasPrefix(lyricsPathPrefix)
        else { return }

        let now = Date()
        try? fm.setAttributes([.modificationDate: now], ofItemAtPath: standardizedURL.path)
        carryProbeMemosAcrossTouch(of: standardizedURL)

        let songDirectory = standardizedURL.hasDirectoryPath
            ? standardizedURL
            : standardizedURL.deletingLastPathComponent()
        if songDirectory != standardizedCacheDirectory,
           songDirectory != standardizedLyricsDirectory
        {
            try? fm.setAttributes([.modificationDate: now], ofItemAtPath: songDirectory.path)
        }
    }

    /// The probe memos are keyed by modification date, which touch() just
    /// bumped; carry any memoized results forward to the new date so the next
    /// lookup doesn't re-open the file with AVAudioFile.
    private static func carryProbeMemosAcrossTouch(of url: URL) {
        let path = url.path
        let modified = modificationDate(of: url)
        probeMemoLock.lock()
        if let entry = durationMemo[path] {
            durationMemo[path] = (modified: modified, duration: entry.duration)
        }
        if let entry = validityMemo[path] {
            validityMemo[path] = (modified: modified, valid: entry.valid)
        }
        probeMemoLock.unlock()
    }

    private static func validateMainSource(for songID: String, expectedRemoteURL: URL?) -> Bool {
        guard let expectedRemoteURL else { return true }
        guard let cachedSource = readMainSourceURL(for: songID) else {
            DebugLogger.log(
                "Discarding legacy audio cache without source metadata for \(songID)",
                category: .cache
            )
            removeSongCache(for: songID)
            return false
        }
        guard cachedSource == expectedRemoteURL.absoluteString else {
            DebugLogger.log(
                "Discarding stale audio cache for \(songID) due to source mismatch",
                category: .cache
            )
            removeSongCache(for: songID)
            return false
        }
        return true
    }

    static func durationAppearsComplete(
        actualDuration: TimeInterval,
        expectedDuration: TimeInterval?
    ) -> Bool {
        guard actualDuration.isFinite, actualDuration > 1.0 else { return false }
        guard let expectedDuration, expectedDuration.isFinite, expectedDuration > 1.0 else {
            return true
        }
        let tolerance = max(5.0, min(15.0, expectedDuration * 0.03))
        return actualDuration + tolerance >= expectedDuration
    }

    private static func readMainSourceURL(for songID: String) -> String? {
        let sourceURL = files(for: songID).mainSource
        guard let data = try? Data(contentsOf: sourceURL),
              let rawValue = String(data: data, encoding: .utf8)
        else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static let minimumPlayableFileSize = 4096

    private static func playableURL(for url: URL) -> URL? {
        // The compressor deletes wav files it has compressed; only hand out an
        // existing file while holding the same lock so it cannot be deleted
        // between the existence check and the return. When the lock is busy,
        // fall through to the compressed copy instead of racing the delete.
        if compressionLock.try() {
            defer { compressionLock.unlock() }
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
            // The fresh decompression bumped the wav's modification date;
            // touch the producing .nkz too so compressedIsCurrent doesn't see
            // it as stale and recompress the pair after every play.
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
        let path = url.path
        let modified = modificationDate(of: url)
        probeMemoLock.lock()
        if let entry = validityMemo[path], entry.modified == modified {
            probeMemoLock.unlock()
            return entry.valid
        }
        probeMemoLock.unlock()
        let valid: Bool = {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size >= minimumPlayableFileSize else { return false }
            return AVEnginePlayback.hasValidAudioHeader(at: url)
        }()
        probeMemoLock.lock()
        if validityMemo.count >= probeMemoLimit { validityMemo.removeAll() }
        validityMemo[path] = (modified, valid)
        probeMemoLock.unlock()
        return valid
    }

    static func audioDuration(at url: URL) -> TimeInterval {
        let path = url.path
        let modified = modificationDate(of: url)
        probeMemoLock.lock()
        if let entry = durationMemo[path], entry.modified == modified {
            probeMemoLock.unlock()
            return entry.duration
        }
        probeMemoLock.unlock()
        var duration: TimeInterval = 0
        if let file = try? AVAudioFile(forReading: url) {
            let sampleRate = file.fileFormat.sampleRate
            if sampleRate > 0 {
                let candidate = Double(file.length) / sampleRate
                if candidate.isFinite, candidate > 0 { duration = candidate }
            }
        }
        probeMemoLock.lock()
        if durationMemo.count >= probeMemoLimit { durationMemo.removeAll() }
        durationMemo[path] = (modified, duration)
        probeMemoLock.unlock()
        return duration
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
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

    // Callers must hold compressionLock (see compressIdleAssets /
    // compressAssets(for:)); the wav deletes here race playableURL otherwise.
    private static func compressPlayableFileIfNeeded(at url: URL) {
        guard shouldCompressPlayableFile(at: url), !Task.isCancelled else { return }
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
        } catch is CancellationError {
            try? fm.removeItem(at: compressed)
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
                try Task.checkCancellation()
                let chunk = try reader.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                try filter.write(chunk)
            }
            try Task.checkCancellation()
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
