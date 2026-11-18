import Foundation
import Observation
import Synchronization
import Testing
@testable import Twinskaraoke

/// The radio polls every 15 seconds. A poll that returns what is already
/// shown must not notify `nowPlaying`'s readers: the radio player layout
/// reads it and stays mounted inside the closed full-screen player.
@MainActor
@Suite("Radio now-playing writes")
struct RadioNowPlayingWriteTests {
    private static let payload = Data("""
        {
          "station": { "name": "Neuro 21", "description": "Live", "listen_url": "https://example.com/live" },
          "listeners": { "total": 12, "unique": 10 },
          "now_playing": { "song": { "id": "a", "art": null, "text": "Artist - Title", "artist": "Artist", "title": "Title" } },
          "playing_next": null,
          "song_history": []
        }
        """.utf8)

    @Test func anUnchangedPollLeavesNowPlayingReadersAlone() async throws {
        let controller = RadioController(loadMetadata: { Self.payload })
        await controller.refresh()
        try #require(controller.nowPlaying != nil)

        let notified = Mutex(false)
        withObservationTracking {
            _ = controller.nowPlaying
        } onChange: {
            notified.withLock { $0 = true }
        }
        await controller.refresh()

        #expect(!notified.withLock { $0 })
        // "Updated …" still moves on: the poll did succeed.
        #expect(controller.lastUpdated != nil)
    }

    @Test func aChangedPollStillNotifies() async throws {
        var listeners = 12
        let controller = RadioController(loadMetadata: {
            let json = String(decoding: Self.payload, as: UTF8.self)
                .replacingOccurrences(of: "\"total\": 12", with: "\"total\": \(listeners)")
            return Data(json.utf8)
        })
        await controller.refresh()
        try #require(controller.nowPlaying?.listeners?.total == 12)

        let notified = Mutex(false)
        withObservationTracking {
            _ = controller.nowPlaying
        } onChange: {
            notified.withLock { $0 = true }
        }
        listeners = 13
        await controller.refresh()

        #expect(notified.withLock { $0 })
        #expect(controller.nowPlaying?.listeners?.total == 13)
    }
}
