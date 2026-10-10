import AppIntents
import AVFoundation
import Foundation
import Testing
@testable import Twinskaraoke

@Suite("System intent playback", .serialized)
@MainActor
struct SystemIntentPlaybackTests {
    @Test func intentsControlActualCachedAudioAndPublishSnapshots() async throws {
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

    @Test func repeatReplaysTheSongThatEnded() async throws {
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

        // Repeat plays the song again every time it ends.
        player.repeatMode = .all
        player.playNextOrRandom()
        player.playNextOrRandom()
        #expect(player.currentSong?.id == songs[0].id)
        #expect(player.repeatMode == .all)

        // Repeat Once plays it one more time, then switches itself off.
        player.repeatMode = .one
        player.playNextOrRandom()
        #expect(player.currentSong?.id == songs[0].id)
        #expect(player.repeatMode == .off)
        player.playNextOrRandom()
        #expect(player.currentSong?.id == songs[1].id)

        // Next leaves the song and keeps the mode for the one it lands on.
        player.repeatMode = .all
        player.skipToNext()
        #expect(player.currentSong?.id == songs[2].id)
        #expect(player.repeatMode == .all)
        #expect(player.queue.map(\.id) == songs.map(\.id))
    }

    private func cachedSong(index: Int) throws -> Song {
        let id = "system-intent-test-\(UUID().uuidString)-\(index)"
        _ = AudioCacheStore.ensureSongDirectory(for: id)
        let url = AudioCacheStore.mainAudioURL(for: id, sourceURL: URL(string: "https://example.invalid/silence.wav")!)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        for _ in 0..<60 { try file.write(from: buffer) }
        return Song(id: id, title: "Widget Test \(index + 1)", duration: 60, absolutePath: nil, cloudflareID: nil, coverArt: nil, originalArtists: ["Simulator"], coverArtists: nil, userUploaded: true)
    }
}
