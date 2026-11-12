import AppIntents
import AVFoundation
import Foundation
import Testing
@testable import Twinskaraoke

/// Whether this machine can play audio at all. VMs and some CI runners have no
/// audio output device: `AVAudioEngine` can't start (error -10851), so a test
/// that needs real playback can't pass there. Only that error means "no
/// device"; any other failure to start returns true, so the test runs and
/// shows it. Starting the engine is the only reliable probe: without a device
/// the output node can't even be configured, and the audio session still
/// reports a built-in speaker.
nonisolated private let audioOutputAvailable: Bool = {
    let engine = AVAudioEngine()
    _ = engine.mainMixerNode
    do {
        try engine.start()
        engine.stop()
        return true
    } catch let error as NSError where error.code == -10851 {
        return false
    } catch {
        return true
    }
}()

@Suite("System intent playback", .serialized)
@MainActor
struct SystemIntentPlaybackTests {
    @Test(.enabled(if: audioOutputAvailable, "Needs an audio output device, and this machine has none."))
    func intentsControlActualCachedAudioAndPublishSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WidgetSnapshotStore(directory: directory)
        let publisher = WidgetSnapshotPublisher.shared
        let previousStore = publisher.store
        publisher.store = store
        defer {
            publisher.store = previousStore
            try? FileManager.default.removeItem(at: directory)
        }
        let player = AudioPlayerManager.shared
        let previousAI = player.aiEnabled
        player.aiEnabled = false
        let songs = try (0..<3).map { try cachedSong(index: $0) }
        defer {
            player.pauseIfPlaying()
            player.sleepTimer.cancel()
            player.aiEnabled = previousAI
            for song in songs { AudioCacheStore.removeSongCache(for: song.id) }
        }
        player.playInOrder(song: songs[0], context: songs)
        try await Task.sleep(for: .milliseconds(300))
        #expect(player.isPlaying)
        _ = try await IOSTogglePlaybackIntent().perform()
        #expect(!player.isPlaying)
        #expect(!store.readPlayback().isPlaying)
        _ = try await IOSTogglePlaybackIntent().perform()
        #expect(player.isPlaying)
        #expect(store.readPlayback().isPlaying)
        _ = try await IOSNextTrackIntent().perform()
        #expect(player.currentSong?.id == songs[1].id)
        player.seek(to: 0)
        _ = try await IOSPreviousTrackIntent().perform()
        #expect(player.currentSong?.id == songs[0].id)
        _ = try await IOSToggleShuffleIntent().perform()
        #expect(player.isShuffled)
        #expect(store.readPlayback().isShuffled)
        _ = try await IOSToggleShuffleIntent().perform()
        #expect(!player.isShuffled)
        #expect(player.queue.map(\.id) == songs.map(\.id))
        player.repeatMode = .off
        for expected in ["one", "all", "off"] {
            _ = try await IOSToggleRepeatIntent().perform()
            #expect(String(describing: player.repeatMode) == expected)
            #expect(store.readPlayback().repeatMode == expected)
        }
        let timer = IOSStartSleepTimerIntent()
        timer.duration = .thirty
        _ = try await timer.perform()
        #expect(player.sleepTimer.deadline != nil)
        #expect(abs(player.sleepTimer.deadline!.timeIntervalSinceNow - 1800) < 5)
        timer.duration = .endOfSong
        _ = try await timer.perform()
        #expect(player.sleepTimer.endsWithCurrentSong)
        #expect(player.sleepTimer.deadline == nil)
        player.repeatMode = .off
        player.currentSong = nil
        do {
            _ = try await IOSNextTrackIntent().perform()
            Issue.record("Empty playback unexpectedly accepted Next Track")
        } catch SystemIntentError.noNext { }
    }

    @Test func repeatLoopsCollectionsAndRepeatsSingleSelections() async throws {
        let player = AudioPlayerManager.shared
        let previousAI = player.aiEnabled
        player.aiEnabled = false
        let songs = try (0..<3).map { try cachedSong(index: $0) }
        defer {
            player.pauseIfPlaying()
            player.repeatMode = .off
            player.aiEnabled = previousAI
            for song in songs { AudioCacheStore.removeSongCache(for: song.id) }
        }
        player.playInOrder(song: songs[0], context: songs)
        try await Task.sleep(for: .milliseconds(300))
        #expect(player.currentSong?.id == songs[0].id)

        // Each end starts near the end of the song, so a replay that did not
        // actually start the song over would leave the progress there.
        func endSong() {
            player.progress = 0.95
            player.playNextOrRandom()
        }

        // Continuous repeat walks the full collection and wraps to its start.
        player.repeatMode = .all
        for index in [1, 2, 0, 1, 2, 0] {
            endSong()
            #expect(player.currentSong?.id == songs[index].id)
            #expect(player.progress == 0)
        }
        #expect(player.repeatMode == .all)

        // Repeat Once plays it one more time, then switches itself off.
        player.repeatMode = .one
        endSong()
        #expect(player.currentSong?.id == songs[0].id)
        #expect(player.progress == 0)
        #expect(player.repeatMode == .off)
        endSong()
        #expect(player.currentSong?.id == songs[1].id)

        // Next leaves the song and keeps the mode for the one it lands on.
        player.repeatMode = .all
        player.skipToNext()
        #expect(player.currentSong?.id == songs[2].id)
        #expect(player.repeatMode == .all)
        #expect(player.queue.map(\.id) == songs.map(\.id))

        // A direct song selection repeats itself, even with a list available
        // as normal context. Repeat does not fetch or append autoplay songs.
        player.play(song: songs[1], context: songs)
        for _ in 0..<3 {
            endSong()
            #expect(player.currentSong?.id == songs[1].id)
            #expect(player.progress == 0)
            #expect(player.queue.map(\.id) == songs.map(\.id))
        }

        // Skipping out of a direct selection can start recommendations while
        // Repeat All stays on. Exercise the same entry point as the async fetch.
        for shuffled in [false, true] {
            if player.isShuffled != shuffled { player.toggleShuffle() }
            player.playAutoplay(song: songs[0], context: songs)
            #expect(player.isShuffled == shuffled)
            let cycle = player.queue
            #expect(cycle.first?.id == songs[0].id)
            for expected in cycle.dropFirst() + [cycle[0]] {
                endSong()
                #expect(player.currentSong?.id == expected.id)
                #expect(player.progress == 0)
                #expect(player.repeatMode == .all)
                #expect(player.queue == cycle)
            }
            if shuffled {
                player.toggleShuffle()
                #expect(player.queue == songs)
            }
            player.play(song: songs[1], context: songs)
            endSong()
            #expect(player.currentSong?.id == songs[1].id)
        }
    }

    @Test(
        "Downloaded songs overlap across Repeat All while the countdown runs",
        .enabled(if: audioOutputAvailable, "Needs an audio output device."),
        arguments: [false, true]
    )
    func downloadedRepeatAllTransition(autoMix: Bool) async throws {
        let player = AudioPlayerManager.shared
        let downloads = DownloadManager.shared
        let previous = (player.aiEnabled, player.autoMixEnabled, player.crossfadeEnabled, player.crossfadeSeconds)
        let songs = try (0..<2).map { try cachedSong(index: $0, seconds: 4) }
        defer {
            player.pauseIfPlaying()
            player.setSleepTimer()
            player.repeatMode = .off
            (player.aiEnabled, player.autoMixEnabled, player.crossfadeEnabled, player.crossfadeSeconds) = previous
            downloads.remove(songIDs: songs.map(\.id))
            for song in songs { AudioCacheStore.removeSongCache(for: song.id) }
        }

        for song in songs {
            let source = try #require(AudioCacheStore.immediatelyPlayableMainURL(
                for: song.id, expectedRemoteURL: nil, expectedDuration: TimeInterval(song.duration)
            ))
            let directory = downloads.localURL(for: song.id).deletingLastPathComponent()
            let destination = directory.appendingPathComponent("main.wav")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
            let resolved = try await downloads.resolvedPlaybackURL(for: song)
            #expect(resolved == destination)
            AudioCacheStore.removeSongCache(for: song.id)
        }

        player.aiEnabled = false
        player.autoMixEnabled = autoMix
        player.crossfadeEnabled = !autoMix
        player.crossfadeSeconds = 1
        player.repeatMode = .all
        player.setSleepTimer(minutes: 5)
        player.playInOrder(song: songs[1], context: songs)

        try await waitForPlayback { player.hasAudibleCrossfadeForTesting && player.currentSong?.id == songs[1].id }
        let wrapDeadline = ContinuousClock.now + .seconds(8)
        while player.currentSong?.id == songs[1].id, ContinuousClock.now < wrapDeadline {
            try await Task.sleep(for: .milliseconds(15))
        }
        try #require(player.currentSong?.id == songs[0].id)
        #expect(player.playbackTime > 0.2)
        #expect(player.sleepTimer.deadline != nil)

        player.startSleepTimerAtEndOfSong()
        let stopDeadline = ContinuousClock.now + .seconds(8)
        while player.isPlaying, ContinuousClock.now < stopDeadline {
            try await Task.sleep(for: .milliseconds(15))
        }
        #expect(!player.isPlaying)
        #expect(player.currentSong?.id == songs[0].id)
        #expect(!player.sleepTimer.isActive)
    }

    @Test func repeatAllAdvancesThroughDuplicatePlaylistEntries() throws {
        let player = AudioPlayerManager.shared
        let previousAI = player.aiEnabled
        player.aiEnabled = false
        let songs = try (0..<3).map { try cachedSong(index: $0, seconds: 4) }
        let queue = [songs[0], songs[1], songs[0], songs[2]]
        defer {
            player.pauseIfPlaying()
            player.repeatMode = .off
            player.aiEnabled = previousAI
            for song in songs { AudioCacheStore.removeSongCache(for: song.id) }
        }
        player.repeatMode = .all
        player.playInOrder(song: queue[0], context: queue)
        for song in queue.dropFirst() + [queue[0]] {
            player.playNextOrRandom()
            #expect(player.currentSong?.id == song.id)
        }
        #expect(player.queue == queue)
    }

    @Test(
        "Removing an audible crossfade target keeps the remaining queue",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func removesAudibleCrossfadeTarget() async throws {
        let player = AudioPlayerManager.shared
        let previous = (player.aiEnabled, player.autoMixEnabled, player.crossfadeEnabled, player.crossfadeSeconds)
        let songs = try (0..<3).map { try cachedSong(index: $0, seconds: 5) }
        defer {
            player.pauseIfPlaying()
            player.repeatMode = .off
            (player.aiEnabled, player.autoMixEnabled, player.crossfadeEnabled, player.crossfadeSeconds) = previous
            for song in songs { AudioCacheStore.removeSongCache(for: song.id) }
        }
        player.aiEnabled = false
        player.crossfadeEnabled = true
        player.crossfadeSeconds = 2
        player.repeatMode = .all
        player.playInOrder(song: songs[0], context: songs)
        try await waitForPlayback { player.currentSong?.id == songs[0].id && player.hasAudibleCrossfadeForTesting }
        try #require(player.upcomingSong?.id == songs[1].id)
        player.removeFromUpNext(at: IndexSet(integer: 0))
        try await waitForPlayback { player.currentSong?.id != songs[0].id }
        #expect(player.currentSong?.id == songs[2].id)
    }

    @Test(
        "Natural end promotes a ready deck only while its queue occurrence is valid",
        .enabled(if: audioOutputAvailable, "Needs an audio output device."),
        arguments: [false, true]
    )
    func naturalEndRespectsCurrentQueueTarget(removeTarget: Bool) async throws {
        let player = AudioPlayerManager.shared
        let previous = (player.aiEnabled, player.autoMixEnabled, player.crossfadeEnabled, player.crossfadeSeconds)
        let songs = try (0..<3).map { try cachedSong(index: $0, seconds: 6) }
        defer {
            player.pauseIfPlaying()
            player.repeatMode = .off
            (player.aiEnabled, player.autoMixEnabled, player.crossfadeEnabled, player.crossfadeSeconds) = previous
            for song in songs { AudioCacheStore.removeSongCache(for: song.id) }
        }
        player.aiEnabled = false
        player.crossfadeEnabled = true
        player.crossfadeSeconds = 1
        player.repeatMode = .off
        player.playInOrder(song: songs[0], context: songs)
        try await waitForPlayback { player.hasPreparedCrossfadeForTesting }
        #expect(!player.hasAudibleCrossfadeForTesting)
        if removeTarget { player.removeFromUpNext(at: [0]) }
        player.finishOutgoingDeckForTesting()
        #expect(player.currentSong?.id == songs[removeTarget ? 2 : 1].id)
    }

    @Test func shuffleDoesNotReplacePendingAutoplayWithPlayback() throws {
        let player = AudioPlayerManager.shared
        let previous = (player.autoplayEnabled, player.repeatMode)
        let songs = try (0..<2).map { try cachedSong(index: $0, seconds: 4) }
        defer {
            player.pauseIfPlaying()
            if player.isShuffled { player.toggleShuffle() }
            (player.autoplayEnabled, player.repeatMode) = previous
            for song in songs { AudioCacheStore.removeSongCache(for: song.id) }
        }
        player.autoplayEnabled = true
        player.repeatMode = .off
        player.playInOrder(song: songs[1], context: songs)
        #expect(player.preservesAutoplayRequestForTesting { player.toggleShuffle() })
        #expect(player.currentSong?.id == songs[1].id)
    }

    private func waitForPlayback(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(15))
        }
        try #require(condition())
    }

    @Test func playsFromAPlaylistReportThatPlaylist() async throws {
        let player = AudioPlayerManager.shared
        let reporter = player.playCountReporter
        let previousAI = player.aiEnabled
        let previousSend = reporter.send
        let previousReadToken = reporter.readToken
        player.aiEnabled = false
        let reports = ReportLog()
        reporter.send = { request in await reports.append(request) }
        reporter.readToken = { nil }
        let songs = try (0..<3).map { try cachedSong(index: $0) }
        let outsider = try cachedSong(index: 3)
        defer {
            player.pauseIfPlaying()
            player.repeatMode = .off
            player.aiEnabled = previousAI
            reporter.send = previousSend
            reporter.readToken = previousReadToken
            for song in songs + [outsider] { AudioCacheStore.removeSongCache(for: song.id) }
        }

        // The playlist's songs carry its ID, including the next one in the queue.
        player.repeatMode = .off
        player.playInOrder(song: songs[0], context: songs, playlistID: "playlist-1")
        #expect(try await reports.next() == Report(songID: songs[0].id, playlistID: "playlist-1"))
        player.skipToNext()
        #expect(try await reports.next() == Report(songID: songs[1].id, playlistID: "playlist-1"))

        // A song added with Play Next isn't part of the playlist.
        player.playNext(song: outsider)
        player.skipToNext()
        #expect(try await reports.next() == Report(songID: outsider.id, playlistID: nil))

        // Picking a playlist song from Up Next keeps the playlist.
        player.skipToQueuedSong(songs[2])
        #expect(try await reports.next() == Report(songID: songs[2].id, playlistID: "playlist-1"))

        // A playlist song queued again with Play Last is a separate addition.
        player.playLast(song: songs[0])
        player.skipToQueuedSong(songs[0])
        #expect(try await reports.next() == Report(songID: songs[0].id, playlistID: nil))

        // An empty shuffle starts nothing, so the playlist stays.
        player.playShuffled(from: [], playlistID: "playlist-x")
        player.skipToQueuedSong(songs[1])
        #expect(try await reports.next() == Report(songID: songs[1].id, playlistID: "playlist-1"))

        // Shuffling a playlist keeps its ID; a queue from anywhere else drops it.
        player.playShuffled(from: songs, playlistID: "playlist-2")
        #expect(try await reports.next()?.playlistID == "playlist-2")
        player.play(song: songs[2], context: songs)
        #expect(try await reports.next() == Report(songID: songs[2].id, playlistID: nil))
        player.playAutoplay(song: songs[0], context: songs)
        #expect(try await reports.next() == Report(songID: songs[0].id, playlistID: nil))
    }

    @Test func aCacheRetryIsNotCountedAsASecondPlay() async throws {
        let player = AudioPlayerManager.shared
        let reporter = player.playCountReporter
        let previousAI = player.aiEnabled
        let previousSend = reporter.send
        let previousReadToken = reporter.readToken
        player.aiEnabled = false
        let reports = ReportLog()
        reporter.send = { request in await reports.append(request) }
        reporter.readToken = { nil }
        let song = try cachedSong(index: 0)
        defer {
            player.pauseIfPlaying()
            player.aiEnabled = previousAI
            reporter.send = previousSend
            reporter.readToken = previousReadToken
            AudioCacheStore.removeSongCache(for: song.id)
        }

        player.play(song: song, context: [song])
        #expect(try await reports.next() == Report(songID: song.id, playlistID: nil))
        // The engine fails on the cached file: the player deletes the cache and
        // retries from the network. That is the same play, not a new one.
        player.avEngine.onPlaybackError?(URLError(.cannotDecodeContentData))
        try await Task.sleep(for: .seconds(1))
        #expect(await reports.total == 1)
    }

    private func cachedSong(index: Int, seconds: Int = 60) throws -> Song {
        let id = "system-intent-test-\(UUID().uuidString)-\(index)"
        _ = AudioCacheStore.ensureSongDirectory(for: id)
        let url = AudioCacheStore.mainAudioURL(for: id, sourceURL: URL(string: "https://example.invalid/silence.wav")!)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        for _ in 0..<seconds { try file.write(from: buffer) }
        return Song(id: id, title: "Widget Test \(index + 1)", duration: seconds, absolutePath: nil, cloudflareID: nil, coverArt: nil, originalArtists: ["Simulator"], coverArtists: nil, userUploaded: true)
    }
}

private struct Report: Equatable, Sendable {
    let songID: String
    let playlistID: String?
}

/// Collects the play-count requests the player sends, so the test can wait
/// for each one instead of sleeping.
private actor ReportLog {
    private var reports: [Report] = []
    private var read = 0
    var total: Int { reports.count }

    func append(_ request: URLRequest) {
        guard let url = request.url else { return }
        let playlistID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "playlistId" }?.value
        reports.append(Report(songID: url.lastPathComponent, playlistID: playlistID))
    }

    /// The next report, waiting up to two seconds for it.
    func next() async throws -> Report? {
        for _ in 0..<200 {
            if read < reports.count {
                read += 1
                return reports[read - 1]
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}
