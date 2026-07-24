import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Download validation")
struct DownloadManagerTests {
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
}
