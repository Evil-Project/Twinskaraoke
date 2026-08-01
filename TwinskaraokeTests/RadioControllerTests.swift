import Foundation
import Testing
@testable import Twinskaraoke

private actor ControlledRadioMetadataLoader {
    private var continuations: [CheckedContinuation<RadioNowPlaying, Error>] = []
    private(set) var requestCount = 0

    func load() async throws -> RadioNowPlaying {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilRequested() async {
        while requestCount == 0 {
            await Task.yield()
        }
    }

    func succeed(with metadata: RadioNowPlaying) {
        continuations.removeFirst().resume(returning: metadata)
    }
}

@MainActor
private final class RadioPlaybackSpy {
    private(set) var requestCount = 0

    func start(streamURL _: URL, song _: Song, artworkURL _: URL?) {
        requestCount += 1
    }
}

@MainActor
@Suite("Radio lifecycle state")
struct RadioControllerTests {
    @Test("Stopping immediately prevents the deferred initial refresh")
    func immediateStopCancelsInitialRefresh() async {
        let loader = ControlledRadioMetadataLoader()
        let controller = RadioController(metadataLoader: { try await loader.load() })

        controller.start()
        controller.stop()
        for _ in 0 ..< 50 {
            await Task.yield()
        }

        #expect(await loader.requestCount == 0)
        #expect(!controller.isRefreshing)
        #expect(controller.nowPlaying == nil)
    }

    @Test("A canceled pending radio request cannot interrupt newer playback")
    func canceledPlaybackRequestDoesNotStartRadio() async {
        let loader = ControlledRadioMetadataLoader()
        let playback = RadioPlaybackSpy()
        let controller = RadioController(
            metadataLoader: { try await loader.load() },
            playbackStarter: playback.start
        )

        controller.playLiveStream()
        await loader.waitUntilRequested()
        controller.cancelPendingPlaybackRequest()
        await loader.succeed(with: makeMetadata())
        for _ in 0 ..< 50 {
            await Task.yield()
        }

        #expect(playback.requestCount == 0)
    }

    @Test("Repeated play taps while metadata loads start radio once")
    func repeatedPlaybackRequestsCoalesce() async {
        let loader = ControlledRadioMetadataLoader()
        let playback = RadioPlaybackSpy()
        let controller = RadioController(
            metadataLoader: { try await loader.load() },
            playbackStarter: playback.start
        )

        controller.playLiveStream()
        await loader.waitUntilRequested()
        controller.playLiveStream()
        await loader.succeed(with: makeMetadata())
        for _ in 0 ..< 50 {
            await Task.yield()
        }

        #expect(playback.requestCount == 1)
    }

    private func makeMetadata() -> RadioNowPlaying {
        RadioNowPlaying(
            station: RadioNowPlaying.Station(
                name: "Twinskaraoke Radio",
                description: "Live karaoke radio",
                listenUrl: "https://radio.twinskaraoke.com/listen/neuro_21/radio.mp3"
            ),
            listeners: nil,
            nowPlaying: nil,
            playingNext: nil,
            songHistory: nil
        )
    }
}
