import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

@MainActor
@Suite("Watch song model")
struct WatchSongModelTests {
    @Test("Watch song URLs normalize storage paths")
    func songAudioURLNormalizesAbsolutePath() {
        UserDefaults.standard.set("global", forKey: "nk.storageRegion")
        let song = Song(
            id: "watch-song-1",
            title: "Watch Song",
            duration: 125,
            absolutePath: "/watch/audio.mp3",
            coverArt: SongMedia(absolutePath: "/covers/watch.jpg"),
            coverArtists: ["Cover Artist"],
            originalArtists: ["Original Artist"],
            cloudflareId: nil,
            userUploaded: false
        )

        #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/watch/audio.mp3")
        #expect(
            song.imageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=480,quality=85,format=webp/covers/watch.jpg/public"
        )
        #expect(
            song.rowImageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=180,quality=78,format=webp/covers/watch.jpg/public"
        )
        #expect(song.artistName == "Original Artist")
        #expect(song.durationText == "2:05")
    }

    @Test("Watch song equality is based on id")
    func equalityUsesSongId() {
        let first = Song(
            id: "same-id",
            title: "First",
            duration: 1,
            absolutePath: "first.mp3",
            coverArt: nil,
            coverArtists: nil,
            originalArtists: nil,
            cloudflareId: nil,
            userUploaded: false
        )
        let second = Song(
            id: "same-id",
            title: "Second",
            duration: 2,
            absolutePath: "second.mp3",
            coverArt: nil,
            coverArtists: nil,
            originalArtists: nil,
            cloudflareId: nil,
            userUploaded: false
        )

        #expect(first == second)
    }
}

@MainActor
@Suite("Watch audio manager queue")
struct WatchAudioManagerQueueTests {
    @Test("Playing without a context clears stale queue state")
    func playWithoutContextUsesSingleSongQueue() {
        let manager = AudioManager()
        let firstContext = [
            makeSong(id: "queue-1", title: "First"),
            makeSong(id: "queue-2", title: "Second"),
        ]
        let standalone = makeSong(id: "solo", title: "Solo")

        manager.play(song: firstContext[1], context: firstContext)
        manager.play(song: standalone)

        #expect(manager.currentSong == standalone)
        #expect(manager.queue == [standalone])
        #expect(manager.currentIndex == 0)
        #expect(manager.upNextSongs.isEmpty)
    }

    @Test("Playing a song outside the provided context keeps the queue valid")
    func playOutsideContextInsertsCurrentSong() {
        let manager = AudioManager()
        let current = makeSong(id: "outside", title: "Outside")
        let context = [
            makeSong(id: "queue-1", title: "First"),
            makeSong(id: "queue-2", title: "Second"),
        ]

        manager.play(song: current, context: context)

        #expect(manager.currentSong == current)
        #expect(manager.queue.first == current)
        #expect(manager.currentIndex == 0)
        #expect(manager.upNextSongs == context)
    }

    @Test("Up next follows the current queue index")
    func upNextUsesCurrentIndex() {
        let manager = AudioManager()
        let songs = [
            makeSong(id: "queue-1", title: "First"),
            makeSong(id: "queue-2", title: "Second"),
            makeSong(id: "queue-3", title: "Third"),
        ]

        manager.play(song: songs[1], context: songs)

        #expect(manager.currentIndex == 1)
        #expect(manager.upNextSongs == [songs[2]])
    }

    private func makeSong(id: String, title: String) -> Song {
        Song(
            id: id,
            title: title,
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Original"],
            coverArtists: ["Cover"],
            userUploaded: false
        )
    }
}


@MainActor
@Suite("Watch audio cache eviction")
struct WatchAudioCacheEvictionTests {
    @Test("Eviction enforces the total byte budget")
    func evictionEnforcesByteBudget() throws {
        let directory = try makeCacheDirectory(fileSizes: [1024, 1024, 1024])
        defer { try? FileManager.default.removeItem(at: directory) }

        AudioManager().evictOldCacheFiles(in: directory, maxCount: 10, maxBytes: 2 * 1024)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(remaining == ["song-1.mp3", "song-2.mp3"])
    }

    @Test("Eviction still enforces the file count limit")
    func evictionEnforcesCountLimit() throws {
        let directory = try makeCacheDirectory(fileSizes: [128, 128, 128, 128])
        defer { try? FileManager.default.removeItem(at: directory) }

        AudioManager().evictOldCacheFiles(in: directory, maxCount: 2, maxBytes: .max)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(remaining == ["song-2.mp3", "song-3.mp3"])
    }

    @Test("Eviction always keeps the newest file even over the byte budget")
    func evictionKeepsNewestFile() throws {
        let directory = try makeCacheDirectory(fileSizes: [4 * 1024])
        defer { try? FileManager.default.removeItem(at: directory) }

        AudioManager().evictOldCacheFiles(in: directory, maxCount: 10, maxBytes: 1024)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(remaining == ["song-0.mp3"])
    }

    /// Writes files named song-N.mp3 with ascending modification dates
    /// (song-0 oldest), mirroring how the cache timestamps downloads.
    private func makeCacheDirectory(fileSizes: [Int]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("eviction-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, size) in fileSizes.enumerated() {
            let url = directory.appendingPathComponent("song-\(index).mp3")
            try Data(repeating: 0x41, count: size).write(to: url)
            let date = Date(timeIntervalSinceNow: Double(index - fileSizes.count) * 60)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return directory
    }
}

@Suite("Watch image cache")
struct WatchImageCacheTests {
    @Test("Failed image fetches enter the negative cache")
    func failedFetchIsNegativelyCached() async {
        // Nothing listens on port 1, so the fetch fails fast.
        let url = URL(string: "http://127.0.0.1:1/watch-image-cache-negative.jpg")!
        let cache = WatchImageCache.shared

        let image = await cache.image(for: url)

        #expect(image == nil)
        #expect(cache.isKnownFailure(for: url))
    }
}
