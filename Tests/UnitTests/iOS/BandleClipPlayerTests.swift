import AVFoundation
import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Bandle clip player")
struct BandleClipPlayerTests {
    private let clipURL = Bundle.main.url(forResource: "BandleFixture", withExtension: "m4a")

    @Test("Playing a clip pauses the app's music first")
    func playPausesAppPlayback() throws {
        var pauses = 0
        let player = BandleClipPlayer(notificationCenter: NotificationCenter(), pauseAppPlayback: { pauses += 1 })
        player.load(url: try #require(clipURL))

        player.play()

        #expect(pauses == 1)
        #expect(player.isPlaying)
    }

    @Test("Music starting elsewhere in the app pauses the clip")
    func appAudioPausesClip() async throws {
        let center = NotificationCenter()
        let player = BandleClipPlayer(notificationCenter: center, pauseAppPlayback: {})
        player.load(url: try #require(clipURL))
        player.play()

        center.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        // The observer hops to the main actor in a task, so give it a turn.
        for _ in 0 ..< 20 where player.isPlaying {
            await Task.yield()
        }

        #expect(!player.isPlaying)
    }

    @Test("A stopped clip can be played again without reloading it")
    func playAfterStop() throws {
        let player = BandleClipPlayer(notificationCenter: NotificationCenter(), pauseAppPlayback: {})
        player.load(url: try #require(clipURL))
        player.play()

        player.stop()
        #expect(!player.isPlaying)
        #expect(player.currentTime == 0)
        player.play()

        #expect(player.isPlaying)
    }

    @Test("Without a clip, Play does nothing and leaves the music alone")
    func playWithoutClip() {
        var pauses = 0
        let player = BandleClipPlayer(notificationCenter: NotificationCenter(), pauseAppPlayback: { pauses += 1 })

        player.play()

        #expect(!player.isPlaying)
        #expect(pauses == 0)
    }
}
