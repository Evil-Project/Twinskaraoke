import AVFoundation
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

    @Test("Watch search songs decode and preserve OSS playback metadata")
    func searchSongConvertsOssOnlyResult() throws {
        UserDefaults.standard.set("global", forKey: "nk.storageRegion")
        let data = try #require(
            """
            {"id":"watch-search-oss","title":"Uploaded","duration":42,"absolutePath":null,"oss":"audio/uploaded.mp3","userUploaded":true}
            """.data(using: .utf8)
        )
        let item = try JSONDecoder().decode(SearchSongItem.self, from: data)
        let song = try #require(item.toSong())

        #expect(item.oss == "audio/uploaded.mp3")
        #expect(item.userUploaded == true)
        #expect(song.absolutePath == nil)
        #expect(song.oss == item.oss)
        #expect(song.userUploaded == true)
        #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/audio/uploaded.mp3")

        let unavailableItem = SearchSongItem(
            id: "watch-search-unavailable",
            title: "Unavailable",
            duration: 0,
            absolutePath: " \n ",
            originalArtists: nil,
            coverArtists: nil,
            coverArt: nil,
            cloudflareId: nil,
            userUploaded: true,
            oss: "\t"
        )
        #expect(unavailableItem.toSong() == nil)
    }
}

@MainActor
@Suite("Watch audio manager queue")
struct WatchAudioManagerQueueTests {
    @Test("Playing without a context clears stale queue state")
    func playWithoutContextUsesSingleSongQueue() {
        let manager = makeManager()
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
        let manager = makeManager()
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
        let manager = makeManager()
        let songs = [
            makeSong(id: "queue-1", title: "First"),
            makeSong(id: "queue-2", title: "Second"),
            makeSong(id: "queue-3", title: "Third"),
        ]

        manager.play(song: songs[1], context: songs)

        #expect(manager.currentIndex == 1)
        #expect(manager.upNextSongs == [songs[2]])
    }

    @Test("Toggling shuffle keeps the current song first and restores order when disabled")
    func toggleShuffleReordersAndRestores() {
        let manager = makeManager()
        let songs = (0 ..< 6).map { makeSong(id: "queue-\($0)", title: "Song \($0)") }
        manager.play(song: songs[2], context: songs)

        manager.toggleShuffle()
        #expect(manager.isShuffleOn)
        #expect(manager.queue.first == songs[2])
        #expect(manager.currentIndex == 0)
        #expect(manager.queue.count == songs.count)
        #expect(manager.queue.map(\.id).sorted() == songs.map(\.id).sorted())

        manager.toggleShuffle()
        #expect(!manager.isShuffleOn)
        #expect(manager.queue == songs)
        #expect(manager.queue[manager.currentIndex] == songs[2])
    }

    @Test("Shuffled next and previous walk the same order so previous returns to the prior song")
    func shuffledNavigationFollowsQueueOrder() {
        let manager = makeManager()
        let songs = (0 ..< 6).map { makeSong(id: "queue-\($0)", title: "Song \($0)") }
        manager.play(song: songs[0], context: songs)
        manager.toggleShuffle()
        let order = manager.queue

        manager.playNext()
        #expect(manager.currentSong == order[1])
        manager.playNext()
        #expect(manager.currentSong == order[2])
        manager.playPrevious()
        #expect(manager.currentSong == order[1])
    }

    @Test("Picking a song from the current queue while shuffled keeps the queue order")
    func playFromCurrentQueueKeepsShuffledOrder() {
        let manager = makeManager()
        let songs = (0 ..< 6).map { makeSong(id: "queue-\($0)", title: "Song \($0)") }
        manager.play(song: songs[0], context: songs)
        manager.toggleShuffle()
        let order = manager.queue

        manager.play(song: order[3], context: manager.queue)
        #expect(manager.queue == order)
        #expect(manager.currentIndex == 3)
        #expect(manager.currentSong == order[3])
    }

    @Test("Playing a new context while shuffled records it for un-shuffle restore")
    func newContextWhileShuffledTracksOriginalOrder() {
        let manager = makeManager()
        let songs = (0 ..< 3).map { makeSong(id: "queue-\($0)", title: "Song \($0)") }
        manager.play(song: songs[1], context: songs)
        manager.toggleShuffle()

        let newSongs = (0 ..< 5).map { makeSong(id: "alt-\($0)", title: "Alt \($0)") }
        manager.play(song: newSongs[4], context: newSongs)
        #expect(manager.queue.first == newSongs[4])
        #expect(manager.queue.count == newSongs.count)
        #expect(manager.queue.map(\.id).sorted() == newSongs.map(\.id).sorted())

        manager.toggleShuffle()
        #expect(manager.queue == newSongs)
        #expect(manager.queue[manager.currentIndex] == newSongs[4])
    }

    @Test("A shuffled outside-context song remains in the queue after restoring order")
    func shuffledOutsideContextRestoresCurrentSong() {
        let manager = makeManager()
        let initial = (0 ..< 3).map { makeSong(id: "queue-\($0)", title: "Song \($0)") }
        manager.play(song: initial[0], context: initial)
        manager.toggleShuffle()

        let current = makeSong(id: "outside", title: "Outside")
        let newContext = (0 ..< 3).map { makeSong(id: "alt-\($0)", title: "Alt \($0)") }
        manager.play(song: current, context: newContext)
        manager.toggleShuffle()

        #expect(manager.currentSong == current)
        #expect(manager.queue.first == current)
        #expect(manager.queue[manager.currentIndex] == current)
        #expect(manager.upNextSongs == newContext)
    }

    @Test("Shuffle preserves duplicate queue entries")
    func shufflePreservesDuplicateEntries() {
        let manager = makeManager()
        let selected = makeSong(id: "repeat", title: "Repeat")
        let duplicate = makeSong(id: "repeat", title: "Repeat Again")
        let other = makeSong(id: "other", title: "Other")
        let songs = [selected, other, duplicate]
        manager.play(song: selected, context: songs)

        manager.toggleShuffle()

        #expect(manager.queue.count == songs.count)
        #expect(manager.queue.count(where: { $0.id == selected.id }) == 2)
        #expect(manager.queue.first == selected)
    }

    @Test("Playing a duplicate id selects the matching queue occurrence")
    func duplicateSelectionUsesFullOccurrence() {
        let manager = makeManager()
        let first = makeSong(id: "repeat", title: "First Copy")
        let middle = makeSong(id: "middle", title: "Middle")
        let second = makeSong(id: "repeat", title: "Second Copy")

        manager.play(song: second, context: [first, middle, second])

        #expect(manager.currentIndex == 2)
        #expect(manager.currentSong?.title == "Second Copy")
        #expect(manager.upNextSongs.isEmpty)
    }

    @Test("Shuffle restores the selected duplicate to its original occurrence")
    func shuffleRestoresSelectedDuplicateOccurrence() {
        let manager = makeManager()
        let first = makeSong(id: "repeat", title: "First Copy")
        let middle = makeSong(id: "middle", title: "Middle")
        let second = makeSong(id: "repeat", title: "Second Copy")
        manager.play(song: first, context: [first, middle, second])
        #expect(manager.playQueueItem(at: 2))

        manager.toggleShuffle()
        #expect(manager.currentIndex == 0)
        #expect(manager.currentSong?.title == "Second Copy")

        manager.toggleShuffle()
        #expect(manager.currentIndex == 2)
        #expect(manager.currentSong?.title == "Second Copy")
        #expect(manager.queue.map(\.title) == ["First Copy", "Middle", "Second Copy"])
    }

    private func makeManager() -> AudioManager {
        AudioManager { _ in
            try await Task.sleep(for: .seconds(3_600))
            throw CancellationError()
        }
    }

    private func makeSong(id: String, title: String) -> Song {
        Song(
            id: id,
            title: title,
            duration: 180,
            absolutePath: "/audio/\(id).mp3",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Original"],
            coverArtists: ["Cover"],
            userUploaded: false
        )
    }
}

@Suite("Watch player item failure sequence")
struct WatchPlayerItemFailureSequenceTests {
    @Test("A one-song queue recovers once and then stops")
    func oneSongQueueStopsAfterRecoveryFails() {
        var sequence = PlayerItemFailureSequence()

        #expect(
            sequence.resolve(
                queueCount: 1,
                currentIndex: 0,
                playbackRequested: true,
                cacheRecoveryAvailable: true
            ) == .recoverCurrent
        )
        #expect(
            sequence.resolve(
                queueCount: 1,
                currentIndex: 0,
                playbackRequested: true,
                cacheRecoveryAvailable: true
            ) == .stop
        )
    }

    @Test("An all-unplayable queue advances once through every entry and stops")
    func allUnplayableQueueStopsAfterOnePass() {
        var sequence = PlayerItemFailureSequence()

        for index in 0 ..< 3 {
            #expect(
                sequence.resolve(
                    queueCount: 3,
                    currentIndex: index,
                    playbackRequested: true,
                    cacheRecoveryAvailable: true
                ) == .recoverCurrent
            )
            let expected: PlayerItemFailureSequence.Resolution = if index < 2 {
                .advance(to: index + 1)
            } else {
                .stop
            }
            #expect(
                sequence.resolve(
                    queueCount: 3,
                    currentIndex: index,
                    playbackRequested: true,
                    cacheRecoveryAvailable: true
                ) == expected
            )
        }
    }

    @Test("A failure after playback is paused cannot advance the queue")
    func pausedPlaybackStopsFailureHandling() {
        var sequence = PlayerItemFailureSequence()

        #expect(
            sequence.resolve(
                queueCount: 3,
                currentIndex: 0,
                playbackRequested: false,
                cacheRecoveryAvailable: true
            ) == .stop
        )
    }
}

private actor ControlledWatchSearchLoader {
    private var continuations: [String: CheckedContinuation<[SearchSongItem], Error>] = [:]

    func load(query: String) async throws -> [SearchSongItem] {
        try await withCheckedThrowingContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func waitUntilRegistered(_ query: String) async {
        while continuations[query] == nil {
            await Task.yield()
        }
    }

    func succeed(_ query: String, with items: [SearchSongItem]) {
        continuations.removeValue(forKey: query)?.resume(returning: items)
    }
}

private actor ControlledWatchAudioDownloadLoader {
    enum Failure: Error {
        case simulated
    }

    private var continuations: [URL: CheckedContinuation<(URL, Bool), Error>] = [:]
    private var registrationWaiters: [URL: [CheckedContinuation<Void, Never>]] = [:]

    func load(url: URL) async throws -> (URL, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            continuations[url] = continuation
            let waiters = registrationWaiters.removeValue(forKey: url) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilRegistered(_ url: URL) async {
        guard continuations[url] == nil else { return }
        await withCheckedContinuation { continuation in
            registrationWaiters[url, default: []].append(continuation)
        }
    }

    func isRegistered(_ url: URL) -> Bool {
        continuations[url] != nil
    }

    func fail(_ url: URL) {
        continuations.removeValue(forKey: url)?.resume(throwing: Failure.simulated)
    }

    func succeed(_ url: URL, temporaryURL: URL, responseAccepted: Bool = true) {
        continuations.removeValue(forKey: url)?.resume(
            returning: (temporaryURL, responseAccepted)
        )
    }
}

@MainActor
@Suite("Watch audio download state", .serialized)
struct WatchAudioDownloadStateTests {
    @Test("A canceled download completion cannot clear its replacement's loading state")
    func staleDownloadFailureIsIgnored() async throws {
        let loader = ControlledWatchAudioDownloadLoader()
        let manager = AudioManager { url in
            try await loader.load(url: url)
        }
        let first = makeSong(id: "download-first")
        let second = makeSong(id: "download-second")
        let firstURL = try #require(first.audioURL)
        let secondURL = try #require(second.audioURL)

        manager.play(song: first)
        await loader.waitUntilRegistered(firstURL)

        manager.play(song: second)
        await loader.waitUntilRegistered(secondURL)
        #expect(manager.isLoading)
        #expect(manager.currentSong == second)

        await loader.fail(firstURL)
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        #expect(manager.isLoading)
        #expect(manager.currentSong == second)

        await loader.fail(secondURL)
        for _ in 0 ..< 100 where manager.isLoading {
            await Task.yield()
        }

        #expect(!manager.isLoading)
        #expect(manager.currentSong == second)
    }

    @Test("A canceled successful download removes its abandoned temporary file")
    func staleDownloadSuccessRemovesTemporaryFile() async throws {
        let loader = ControlledWatchAudioDownloadLoader()
        let manager = AudioManager { url in
            try await loader.load(url: url)
        }
        let first = makeSong(id: "download-stale-success")
        let second = makeSong(id: "download-current")
        let firstURL = try #require(first.audioURL)
        let secondURL = try #require(second.audioURL)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "watch-stale-\(UUID().uuidString).mp3")
        try Data("abandoned".utf8).write(to: temporaryURL)

        manager.play(song: first)
        await loader.waitUntilRegistered(firstURL)
        manager.play(song: second)
        await loader.waitUntilRegistered(secondURL)

        await loader.succeed(firstURL, temporaryURL: temporaryURL)
        for _ in 0 ..< 100 where FileManager.default.fileExists(atPath: temporaryURL.path) {
            await Task.yield()
        }

        #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
        #expect(manager.isLoading)
        #expect(manager.currentSong == second)

        await loader.fail(secondURL)
    }

    @Test("A download failure advances the queue and stops after one failed pass")
    func downloadFailureUsesQueueRecovery() async throws {
        let loader = ControlledWatchAudioDownloadLoader()
        let manager = AudioManager { url in
            try await loader.load(url: url)
        }
        let first = makeSong(id: "download-recovery-first-\(UUID().uuidString)")
        let second = makeSong(id: "download-recovery-second-\(UUID().uuidString)")
        let firstURL = try #require(first.audioURL)
        let secondURL = try #require(second.audioURL)

        manager.play(song: first, context: [first, second])
        await loader.waitUntilRegistered(firstURL)
        await loader.fail(firstURL)
        await loader.waitUntilRegistered(secondURL)

        #expect(manager.currentIndex == 1)
        #expect(manager.currentSong == second)
        #expect(manager.playbackRequested)
        #expect(manager.isLoading)

        await loader.fail(secondURL)
        for _ in 0 ..< 100 where manager.playbackRequested || manager.isLoading {
            await Task.yield()
        }

        #expect(!manager.playbackRequested)
        #expect(!manager.isLoading)
        #expect(manager.currentIndex == 1)
    }

    @Test("A song without a remote URL advances to the next queue item")
    func missingRemoteURLUsesQueueRecovery() async throws {
        let loader = ControlledWatchAudioDownloadLoader()
        let manager = AudioManager { url in
            try await loader.load(url: url)
        }
        let first = Song(
            id: "missing-remote-\(UUID().uuidString)",
            title: "Missing Remote",
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Original"],
            coverArtists: ["Cover"],
            userUploaded: false
        )
        let second = makeSong(id: "remote-fallback-\(UUID().uuidString)")
        let secondURL = try #require(second.audioURL)

        manager.play(song: first, context: [first, second])
        await loader.waitUntilRegistered(secondURL)

        #expect(manager.currentIndex == 1)
        #expect(manager.currentSong == second)
        #expect(manager.playbackRequested)
        #expect(manager.isLoading)

        await loader.fail(secondURL)
    }

    @Test("A rejected download is treated as a queue item failure")
    func rejectedDownloadUsesQueueRecovery() async throws {
        let loader = ControlledWatchAudioDownloadLoader()
        let manager = AudioManager { url in
            try await loader.load(url: url)
        }
        let first = makeSong(id: "store-rejected-first-\(UUID().uuidString)")
        let second = makeSong(id: "store-rejected-second-\(UUID().uuidString)")
        let firstURL = try #require(first.audioURL)
        let secondURL = try #require(second.audioURL)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "watch-rejected-\(UUID().uuidString).mp3")
        try Data("not audio".utf8).write(to: temporaryURL)

        manager.play(song: first, context: [first, second])
        await loader.waitUntilRegistered(firstURL)
        await loader.succeed(
            firstURL,
            temporaryURL: temporaryURL,
            responseAccepted: false
        )
        await loader.waitUntilRegistered(secondURL)

        #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
        #expect(manager.currentIndex == 1)
        #expect(manager.currentSong == second)
        #expect(manager.playbackRequested)

        await loader.fail(secondURL)
    }

    @Test("Downloaded audio validation failure advances to the next queue item")
    func downloadedValidationFailureUsesQueueRecovery() async throws {
        let loader = ControlledWatchAudioDownloadLoader()
        let manager = AudioManager(
            downloadLoader: { url in
                try await loader.load(url: url)
            },
            audioValidator: { _, _ in false }
        )
        let first = makeSong(id: "validation-first-\(UUID().uuidString)")
        let second = makeSong(id: "validation-second-\(UUID().uuidString)")
        let firstURL = try #require(first.audioURL)
        let secondURL = try #require(second.audioURL)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "watch-invalid-audio-\(UUID().uuidString).mp3")
        try Data([0x49, 0x44, 0x33, 0x00, 0x00, 0x00, 0x00, 0x00]).write(to: temporaryURL)

        manager.play(song: first, context: [first, second])
        await loader.waitUntilRegistered(firstURL)
        await loader.succeed(firstURL, temporaryURL: temporaryURL)

        for _ in 0 ..< 100 {
            if await loader.isRegistered(secondURL) { break }
            await Task.yield()
        }

        let secondRegistered = await loader.isRegistered(secondURL)
        #expect(secondRegistered)
        #expect(manager.currentIndex == 1)
        #expect(manager.currentSong == second)
        #expect(manager.playbackRequested)

        await loader.fail(secondURL)
    }

    @Test("An interruption without options clears its pending resume intent")
    func interruptionWithoutOptionsClearsResumeIntent() async throws {
        let loader = ControlledWatchAudioDownloadLoader()
        let manager = AudioManager { url in
            try await loader.load(url: url)
        }
        let song = makeSong(id: "interrupted-download")
        let remoteURL = try #require(song.audioURL)

        manager.play(song: song)
        await loader.waitUntilRegistered(remoteURL)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
            ]
        )

        // This unrelated end notification must not consume stale resume intent
        // from the prior malformed notification.
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey:
                    AVAudioSession.InterruptionOptions.shouldResume.rawValue,
            ]
        )

        #expect(!manager.playbackRequested)
        #expect(manager.isLoading)

        await loader.fail(remoteURL)
    }

    @Test("Cancel loading during an interruption prevents automatic resume")
    func cancelLoadingDuringInterruptionPreventsResume() async throws {
        let loader = ControlledWatchAudioDownloadLoader()
        let manager = AudioManager { url in
            try await loader.load(url: url)
        }
        let song = makeSong(id: "cancel-interrupted-download")
        let remoteURL = try #require(song.audioURL)

        manager.play(song: song)
        await loader.waitUntilRegistered(remoteURL)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )

        #expect(manager.isLoading)
        #expect(manager.togglePlayPause())
        #expect(!manager.isLoading)
        #expect(!manager.playbackRequested)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey:
                    AVAudioSession.InterruptionOptions.shouldResume.rawValue,
            ]
        )

        #expect(!manager.isLoading)
        #expect(!manager.playbackRequested)
        await loader.fail(remoteURL)
    }

    private func makeSong(id: String) -> Song {
        let uniqueID = "\(id)-\(UUID().uuidString)"
        return Song(
            id: uniqueID,
            title: id,
            duration: 180,
            absolutePath: "/audio/\(uniqueID).mp3",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Original"],
            coverArtists: ["Cover"],
            userUploaded: false
        )
    }
}

@MainActor
@Suite("Watch search state")
struct WatchSearchViewModelTests {
    @Test("A stale search cannot hide the current loader or replace its results")
    func staleSearchCompletionIsIgnored() async {
        let loader = ControlledWatchSearchLoader()
        let viewModel = SearchViewModel { query, _ in
            try await loader.load(query: query)
        }

        viewModel.performSearch(query: "first")
        await loader.waitUntilRegistered("first")

        viewModel.performSearch(query: "second")
        await loader.waitUntilRegistered("second")

        #expect(viewModel.isLoading)
        #expect(viewModel.results.isEmpty)

        await loader.succeed("first", with: [makeSearchItem(id: "old", title: "Old Result")])
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        #expect(viewModel.isLoading)
        #expect(viewModel.results.isEmpty)

        await loader.succeed("second", with: [makeSearchItem(id: "new", title: "New Result")])
        for _ in 0 ..< 100 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(!viewModel.isLoading)
        #expect(viewModel.results.map(\.id) == ["new"])
        #expect(viewModel.searchErrorMessage == nil)
    }

    private func makeSearchItem(id: String, title: String) -> SearchSongItem {
        SearchSongItem(
            id: id,
            title: title,
            duration: 180,
            absolutePath: "/audio/\(id).mp3",
            originalArtists: ["Original"],
            coverArtists: ["Cover"],
            coverArt: nil,
            cloudflareId: nil
        )
    }
}

@Suite("Watch playback control presentation")
struct WatchPlaybackControlPresentationTests {
    @Test("Loading, playing, and paused actions have distinct VoiceOver labels")
    func actionLabelsMatchPlaybackState() {
        #expect(
            WatchPlaybackControlPresentation.actionLabel(
                songTitle: "Hero",
                isLoading: true,
                isPlaying: false
            ) == "Cancel loading Hero"
        )
        #expect(
            WatchPlaybackControlPresentation.actionLabel(
                songTitle: "Hero",
                isLoading: false,
                isPlaying: true
            ) == "Pause Hero"
        )
        #expect(
            WatchPlaybackControlPresentation.actionLabel(
                songTitle: "Hero",
                isLoading: false,
                isPlaying: false
            ) == "Play Hero"
        )
    }
}
