import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Download validation")
struct DownloadManagerTests {
    @Test("Cancelled promotion discards only its own files", arguments: [false, true])
    func cancelledPromotionDoesNotPublishOrDeleteRetry(hasReplacement: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let promotion = DownloadCachePromotion(
            stagedAudio: directory.appendingPathComponent("main.promoting-old.mp3"),
            stagedSource: directory.appendingPathComponent("main.source.promoting-old"),
            audio: directory.appendingPathComponent("main.mp3"),
            source: directory.appendingPathComponent("main.source"),
            directory: directory
        )
        try Data("cancelled".utf8).write(to: promotion.stagedAudio)
        try Data("old-source".utf8).write(to: promotion.stagedSource)
        if hasReplacement {
            try Data("replacement".utf8).write(to: promotion.audio)
            try Data("new-source".utf8).write(to: promotion.source)
        }
        #expect(try !promotion.commit(ifCurrent: false))
        #expect(!FileManager.default.fileExists(atPath: promotion.stagedAudio.path))
        #expect(!FileManager.default.fileExists(atPath: promotion.stagedSource.path))
        if hasReplacement {
            #expect(try Data(contentsOf: promotion.audio) == Data("replacement".utf8))
            #expect(try Data(contentsOf: promotion.source) == Data("new-source".utf8))
        } else {
            #expect(!FileManager.default.fileExists(atPath: promotion.audio.path))
            #expect(!FileManager.default.fileExists(atPath: promotion.source.path))
        }
    }

    @Test("Accepted promotion publishes its audio and source together")
    func acceptedPromotionPublishesFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let promotion = DownloadCachePromotion(
            stagedAudio: directory.appendingPathComponent("main.promoting-current.mp3"),
            stagedSource: directory.appendingPathComponent("main.source.promoting-current"),
            audio: directory.appendingPathComponent("main.mp3"),
            source: directory.appendingPathComponent("main.source"),
            directory: directory
        )
        try Data("audio".utf8).write(to: promotion.stagedAudio)
        try Data("source".utf8).write(to: promotion.stagedSource)
        #expect(try promotion.commit(ifCurrent: true))
        #expect(try Data(contentsOf: promotion.audio) == Data("audio".utf8))
        #expect(try Data(contentsOf: promotion.source) == Data("source".utf8))
        #expect(!FileManager.default.fileExists(atPath: promotion.stagedAudio.path))
        #expect(!FileManager.default.fileExists(atPath: promotion.stagedSource.path))
    }

    @Test("Fallback artwork selection is stable and bounded")
    func fallbackArtworkSelectionIsDeterministic() {
        let first = FallbackArtProvider.fallbackIndex(for: "song-without-art", count: 12)
        let second = FallbackArtProvider.fallbackIndex(for: "song-without-art", count: 12)
        #expect(first == second)
        #expect((0 ..< 12).contains(first))
        #expect(FallbackArtProvider.fallbackIndex(for: "song", count: 0) == 0)
    }

    @Test("Startup cleanup only removes partial files from before launch")
    func startupCleanupPreservesCurrentPartialFiles() {
        let cutoff = Date()
        #expect(
            AudioCacheStore.shouldRemovePartialFile(
                named: "main.mp3.partial",
                modifiedAt: cutoff.addingTimeInterval(-1),
                createdBefore: cutoff
            )
        )
        #expect(
            !AudioCacheStore.shouldRemovePartialFile(
                named: "main.mp3.partial",
                modifiedAt: cutoff.addingTimeInterval(1),
                createdBefore: cutoff
            )
        )
        #expect(
            !AudioCacheStore.shouldRemovePartialFile(
                named: "main.mp3",
                modifiedAt: cutoff.addingTimeInterval(-1),
                createdBefore: cutoff
            )
        )
        #expect(
            AudioCacheStore.shouldRemovePartialFile(
                named: "main.partial.m4a",
                modifiedAt: cutoff.addingTimeInterval(-1),
                createdBefore: cutoff
            )
        )
    }

    @Test("Playback cache preserves the remote audio container extension")
    func playbackCachePreservesRemoteContainerExtension() throws {
        let remoteURL = try #require(
            URL(string: "https://storage.example.com/Imported%20Song.m4a")
        )

        #expect(
            AudioCacheStore.mainAudioURL(for: "uploaded-song", sourceURL: remoteURL)
                .lastPathComponent == "main.m4a"
        )
        #expect(
            AudioCacheStore.mainPartialAudioURL(for: "uploaded-song", sourceURL: remoteURL)
                .lastPathComponent == "main.partial.m4a"
        )
    }

    @Test("Persistent downloads preserve the remote audio container extension")
    func persistentDownloadsPreserveRemoteContainerExtension() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let m4aSource = try #require(URL(string: "https://storage.example.com/upload.m4a"))
        let mp3Source = try #require(URL(string: "https://storage.example.com/catalog.mp3"))

        #expect(
            DownloadManager.downloadedAudioURL(in: directory, sourceURL: m4aSource)
                .lastPathComponent == "main.m4a"
        )
        #expect(
            DownloadManager.downloadedAudioURL(in: directory, sourceURL: mp3Source)
                .lastPathComponent == "main.mp3"
        )
    }

    @Test("Persistent download commit replaces legacy container variants")
    func persistentDownloadCommitRemovesLegacyVariant() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = try #require(URL(string: "https://storage.example.com/upload.m4a"))
        let finalURL = DownloadManager.downloadedAudioURL(
            in: directory,
            sourceURL: sourceURL
        )
        let stagedURL = directory.appendingPathComponent("incoming.m4a")
        let legacyURL = directory.appendingPathComponent("main.mp3")
        try Data("new".utf8).write(to: stagedURL)
        try Data("legacy".utf8).write(to: legacyURL)

        try DownloadManager.commitDownloadedAudioFile(
            at: stagedURL,
            to: finalURL,
            in: directory
        )

        #expect(try Data(contentsOf: finalURL) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
    }

    @Test("Playback cache commit replaces its destination and removes legacy variants")
    func playbackCacheCommitReplacesDestinationSafely() throws {
        let songID = "cache-commit-\(UUID().uuidString)"
        defer { AudioCacheStore.removeSongCache(for: songID) }

        let m4aSource = try #require(URL(string: "https://storage.example.com/song.m4a"))
        let mp3Source = try #require(URL(string: "https://storage.example.com/song.mp3"))
        let finalURL = AudioCacheStore.mainAudioURL(for: songID, sourceURL: m4aSource)
        let stagedURL = AudioCacheStore.mainPartialAudioURL(for: songID, sourceURL: m4aSource)
        let legacyURL = AudioCacheStore.mainAudioURL(for: songID, sourceURL: mp3Source)
        _ = AudioCacheStore.ensureSongDirectory(for: songID)

        try Data("old".utf8).write(to: finalURL)
        try Data("legacy".utf8).write(to: legacyURL)
        try Data("new".utf8).write(to: stagedURL)

        try AudioCacheStore.commitMainAudioFile(
            at: stagedURL,
            to: finalURL,
            for: songID
        )

        #expect(try Data(contentsOf: finalURL) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
    }

    @Test("Failed playback cache commit preserves the existing destination")
    func failedPlaybackCacheCommitPreservesDestination() throws {
        let songID = "cache-commit-failure-\(UUID().uuidString)"
        defer { AudioCacheStore.removeSongCache(for: songID) }

        let sourceURL = try #require(URL(string: "https://storage.example.com/song.m4a"))
        let finalURL = AudioCacheStore.mainAudioURL(for: songID, sourceURL: sourceURL)
        let missingStagedURL = AudioCacheStore.mainPartialAudioURL(
            for: songID,
            sourceURL: sourceURL
        )
        _ = AudioCacheStore.ensureSongDirectory(for: songID)
        try Data("old".utf8).write(to: finalURL)

        var commitFailed = false
        do {
            try AudioCacheStore.commitMainAudioFile(
                at: missingStagedURL,
                to: finalURL,
                for: songID
            )
        } catch {
            commitFailed = true
        }

        #expect(commitFailed)
        #expect(try Data(contentsOf: finalURL) == Data("old".utf8))
    }

    @Test("Only uncompressed stem formats are selected for compression")
    func cacheCompressionSkipsAlreadyCompressedAudio() {
        #expect(AudioCacheStore.shouldCompressPlayableFile(at: URL(fileURLWithPath: "/tmp/vocals.wav")))
        #expect(!AudioCacheStore.shouldCompressPlayableFile(at: URL(fileURLWithPath: "/tmp/main.mp3")))
        #expect(!AudioCacheStore.shouldCompressPlayableFile(at: URL(fileURLWithPath: "/tmp/main.m4a")))
        #expect(!AudioCacheStore.shouldCompressPlayableFile(at: URL(fileURLWithPath: "/tmp/vocals.wav.nkz")))
    }

    @Test("Catalog rounding and longer files are accepted")
    func durationAcceptsHealthyFiles() {
        #expect(
            DownloadManager.durationAppearsComplete(
                actualDuration: 198,
                expectedDuration: 200
            )
        )
        #expect(
            DownloadManager.durationAppearsComplete(
                actualDuration: 205,
                expectedDuration: 200
            )
        )
        #expect(
            DownloadManager.durationAppearsComplete(
                actualDuration: 180,
                expectedDuration: nil
            )
        )
    }

    @Test("Truncated and unreadable files are rejected")
    func durationRejectsBrokenFiles() {
        #expect(
            !DownloadManager.durationAppearsComplete(
                actualDuration: 120,
                expectedDuration: 200
            )
        )
        #expect(
            !DownloadManager.durationAppearsComplete(
                actualDuration: 0,
                expectedDuration: 200
            )
        )
    }

    @Test("Download status reflects only the requested song")
    func downloadStatusUsesRequestedSong() {
        let downloadedIDs: Set<String> = ["downloaded"]
        let inProgress: Set<String> = ["downloading"]

        #expect(
            SongDownloadStatus.make(
                downloadedIDs: downloadedIDs,
                inProgress: inProgress,
                songID: "downloaded"
            ) == SongDownloadStatus(isDownloaded: true, isDownloading: false)
        )
        #expect(
            SongDownloadStatus.make(
                downloadedIDs: downloadedIDs,
                inProgress: inProgress,
                songID: "downloading"
            ) == SongDownloadStatus(isDownloaded: false, isDownloading: true)
        )
        #expect(
            SongDownloadStatus.make(
                downloadedIDs: downloadedIDs,
                inProgress: inProgress,
                songID: "other"
            ) == SongDownloadStatus(isDownloaded: false, isDownloading: false)
        )
    }

    @Test("Collection download status separates pending and in-flight songs")
    func collectionDownloadStatusClassifiesSongs() {
        let songs = ["downloaded", "downloading", "pending", "overlap"].map { id in
            Song(
                id: id,
                title: id,
                duration: 180,
                absolutePath: "/audio/\(id).mp3",
                cloudflareID: nil,
                coverArt: nil,
                originalArtists: nil,
                coverArtists: nil,
                userUploaded: false
            )
        }

        let status = SongCollectionDownloadStatus.make(
            downloadedIDs: ["downloaded", "overlap"],
            inProgress: ["downloading", "overlap"],
            songs: songs
        )

        #expect(status.pendingSongs.map(\.id) == ["pending"])
        #expect(status.inFlightCount == 2)
    }

    @Test("Audio cache access does not mutate persistent download files")
    func cacheTouchLeavesExternalFilesUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("main.mp3")
        #expect(FileManager.default.createFile(atPath: fileURL.path, contents: Data([0])))

        let originalDate = Date(timeIntervalSince1970: 946_684_800)
        try FileManager.default.setAttributes(
            [.modificationDate: originalDate],
            ofItemAtPath: fileURL.path
        )

        AudioCacheStore.touch(fileURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect(attributes[.modificationDate] as? Date == originalDate)
    }

    @Test("Startup cleanup removes only stale promotion staging files")
    func startupCleanupRemovesStalePromotionFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stale = directory.appendingPathComponent("main.mp3.promoting-stale")
        let current = directory.appendingPathComponent("main.source.promoting-current")
        let download = directory.appendingPathComponent("main.mp3")
        for file in [stale, current, download] {
            #expect(FileManager.default.createFile(atPath: file.path, contents: Data([0])))
        }

        let cutoff = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff.addingTimeInterval(-1)],
            ofItemAtPath: stale.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff.addingTimeInterval(1)],
            ofItemAtPath: current.path
        )

        DownloadManager.removePromotionStagingFiles(in: directory, createdBefore: cutoff)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: current.path))
        #expect(FileManager.default.fileExists(atPath: download.path))
    }

    @Test("Interrupted downloads expose resume data, cancellations do not")
    func resumeDataExtraction() {
        let resumeData = Data([1, 2, 3])
        let interrupted = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSURLSessionDownloadTaskResumeData: resumeData]
        )
        #expect(DownloadManager.resumeData(from: interrupted) == resumeData)

        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(DownloadManager.resumeData(from: cancelled) == nil)

        let noProgress = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(DownloadManager.resumeData(from: noProgress) == nil)
    }

    @Test("Lyrics cache save after clear writes into the recreated directory")
    func lyricsSaveSurvivesClear() {
        let songID = "lyrics-clear-\(UUID().uuidString)"
        let lines = [LyricLine(time: 1, text: "hello", translatedText: nil)]

        LyricsCacheStore.save(lines, songID: songID, variant: .original)
        LyricsCacheStore.clear()
        LyricsCacheStore.save(lines, songID: songID, variant: .original)

        #expect(LyricsCacheStore.load(songID: songID, variant: .original)?.map(\.text) == ["hello"])
    }

    @Test("Lyrics cache clear serializes with concurrent saves")
    func lyricsClearSerializesWithSaves() {
        let songID = "lyrics-race-\(UUID().uuidString)"
        let lines = [LyricLine(time: 1, text: "hello", translatedText: nil)]

        DispatchQueue.concurrentPerform(iterations: 20) { iteration in
            if iteration.isMultiple(of: 2) {
                LyricsCacheStore.clear()
            } else {
                LyricsCacheStore.save(lines, songID: songID, variant: .original)
            }
        }

        LyricsCacheStore.save(lines, songID: songID, variant: .original)
        #expect(LyricsCacheStore.load(songID: songID, variant: .original)?.first?.text == "hello")
    }

    @Test("Decompressing a compressed stem keeps the compressed copy current")
    func decompressTouchesCompressedCopy() throws {
        let songID = "decompress-touch-\(UUID().uuidString)"
        defer { AudioCacheStore.removeSongCache(for: songID) }

        let directory = AudioCacheStore.ensureSongDirectory(for: songID)
        let wavData = Self.makeSilentWAVData(seconds: 2)
        for name in ["vocals.wav", "instruments.wav"] {
            try wavData.write(to: directory.appendingPathComponent(name))
        }
        AudioCacheStore.compressAssets(for: songID)

        let compressedVocals = AudioCacheStore.compressedURL(
            for: directory.appendingPathComponent("vocals.wav")
        )
        #expect(FileManager.default.fileExists(atPath: compressedVocals.path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("vocals.wav").path))

        let stems = try #require(AudioCacheStore.playableStems(for: songID, startOffset: 0))

        // The producing .nkz must not look older than the freshly decompressed
        // wav, or the idle compressor would recompress the pair after every play.
        let wavDate = try #require(
            stems.vocals.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        )
        let compressedDate = try #require(
            compressedVocals.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        )
        #expect(compressedDate >= wavDate)
    }

    /// Minimal PCM WAV (mono, 16-bit silence) large enough to pass the cache's
    /// size floor and readable by AVAudioFile for duration checks.
    private static func makeSilentWAVData(seconds: Int, sampleRate: Int = 8000) -> Data {
        let dataSize = seconds * sampleRate * 2
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.appendLittleEndian(UInt32(36 + dataSize))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.appendLittleEndian(UInt32(16)) // PCM chunk size
        data.appendLittleEndian(UInt16(1)) // PCM format
        data.appendLittleEndian(UInt16(1)) // mono
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2)) // byte rate
        data.appendLittleEndian(UInt16(2)) // block align
        data.appendLittleEndian(UInt16(16)) // bits per sample
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.appendLittleEndian(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
