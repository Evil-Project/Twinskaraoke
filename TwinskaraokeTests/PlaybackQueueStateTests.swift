import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Playback queue state")
struct PlaybackQueueStateTests {
    @Test("Playback session preserves position, shuffle order and unshuffle context")
    func sessionRoundTrip() throws {
        let songs = fixtures(4)
        var queue = PlaybackQueueState()
        queue.beginInOrder(context: songs)
        queue.toggleShuffle(current: songs[1], shuffling: { Array($0.reversed()) })
        let snapshot = PlaybackSessionSnapshot(song: songs[1], queue: queue, position: 42,
            repeatMode: .all, wasPlaying: true)
        let restored = try JSONDecoder().decode(PlaybackSessionSnapshot.self,
            from: JSONEncoder().encode(snapshot))
        #expect(restored.song == songs[1])
        #expect(restored.resumePosition == 42)
        #expect(restored.queue == queue)
        #expect(restored.repeatMode == .all)
        var unshuffled = restored.queue
        unshuffled.toggleShuffle(current: restored.song)
        #expect(unshuffled.items == songs)
    }

    @Test("Restored position is clamped to valid media bounds")
    func restoredPositionBounds() {
        let song = fixtures(1)[0]
        for (position, expected) in [(Double.nan, 0.0), (-10.0, 0.0), (1000.0, 180.0)] {
            let saved = PlaybackSessionSnapshot(song: song, queue: PlaybackQueueState(), position: position,
                repeatMode: .off, wasPlaying: false)
            #expect(saved.resumePosition == expected)
        }
    }

    @Test("Play Next inserts once immediately after the current song")
    func insertNextIsStableAndDeduplicated() {
        let songs = fixtures(4)
        var state = PlaybackQueueState()
        state.beginInOrder(context: songs)

        state.insertNext(songs[3], after: songs[1])
        #expect(state.items.map(\.id) == ["0", "1", "3", "2"])

        state.insertNext(songs[3], after: songs[1])
        #expect(state.items.map(\.id) == ["0", "1", "3", "2"])
    }

    @Test("Disabling shuffle restores the exact original order")
    func shuffleRestoresOriginalOrder() {
        let songs = fixtures(4)
        var state = PlaybackQueueState()
        state.beginInOrder(context: songs)

        state.toggleShuffle(current: songs[1], shuffling: { Array($0.reversed()) })
        #expect(state.isShuffled)
        #expect(state.items.map(\.id) == ["1", "3", "2", "0"])

        state.toggleShuffle(current: songs[1])
        #expect(!state.isShuffled)
        #expect(state.items == songs)
        #expect(state.originalItems.isEmpty)
    }

    @Test("Repeat and autoplay decisions are explicit queue outcomes")
    func advanceMatrix() {
        let songs = fixtures(2)
        var state = PlaybackQueueState()
        state.beginInOrder(context: songs)

        #expect(state.advance(after: songs[0], repeatMode: .off, autoplayEnabled: false) == .play(songs[1]))
        #expect(state.advance(after: songs[1], repeatMode: .one, autoplayEnabled: false) == .replayCurrent)
        #expect(state.advance(after: songs[1], repeatMode: .all, autoplayEnabled: false) == .play(songs[0]))
        #expect(state.advance(after: songs[1], repeatMode: .off, autoplayEnabled: true) == .autoplay)
        #expect(state.advance(after: songs[1], repeatMode: .off, autoplayEnabled: false) == .stop)
    }

    @Test("Next leaves the song under Repeat One; the song ending does not")
    func skipIgnoresRepeatOne() {
        let songs = fixtures(3)
        var state = PlaybackQueueState()
        state.beginInOrder(context: songs)

        #expect(state.advance(after: songs[0], repeatMode: .one, autoplayEnabled: false) == .replayCurrent)
        #expect(state.skip(after: songs[0], repeatMode: .one, autoplayEnabled: false) == .play(songs[1]))
        // At the end, a skip under Repeat One behaves as with repeat off.
        #expect(state.skip(after: songs[2], repeatMode: .one, autoplayEnabled: true) == .autoplay)
        #expect(state.skip(after: songs[2], repeatMode: .one, autoplayEnabled: false) == .stop)
        // Other modes skip exactly as the song ending would.
        #expect(state.skip(after: songs[2], repeatMode: .all, autoplayEnabled: false) == .play(songs[0]))
        #expect(state.skip(after: songs[0], repeatMode: .off, autoplayEnabled: false) == .play(songs[1]))
    }

    @Test("Previous restarts a song a few seconds in, and goes back at its start")
    func previousRestartsPastThreshold() {
        let songs = fixtures(3)
        var state = PlaybackQueueState()
        state.beginInOrder(context: songs)

        #expect(state.previous(before: songs[1], elapsed: 0) == songs[0])
        #expect(state.previous(before: songs[1], elapsed: 2.9) == songs[0])
        #expect(state.previous(before: songs[1], elapsed: 3.1) == nil)
        #expect(state.previous(before: songs[1], elapsed: 125) == nil)
        #expect(state.previous(before: songs[0], elapsed: 0) == nil)
    }

    @Test("Up Next edits cannot alter played queue entries")
    func upNextEditingPreservesHistory() {
        let songs = fixtures(5)
        var state = PlaybackQueueState()
        state.beginInOrder(context: songs)

        state.moveUpNext(after: songs[1], from: IndexSet(integer: 2), to: 0)
        #expect(state.items.map(\.id) == ["0", "1", "4", "2", "3"])

        state.removeUpNext(after: songs[1], at: IndexSet(integer: 1))
        #expect(state.items.map(\.id) == ["0", "1", "4", "3"])
    }

    @Test("Removing shuffled Up Next songs also removes them from restored order")
    func shuffledRemovalPersistsWhenShuffleIsDisabled() throws {
        let songs = fixtures(4)
        var state = PlaybackQueueState()
        let selection = state.beginShuffled(
            songs: songs,
            selecting: { $0[1] },
            shuffling: { Array($0.reversed()) }
        )
        let current = try #require(selection)

        #expect(state.items.map(\.id) == ["1", "3", "2", "0"])
        state.removeUpNext(after: current, at: IndexSet(integer: 0))
        #expect(state.items.map(\.id) == ["1", "2", "0"])

        state.toggleShuffle(current: current)
        #expect(state.items.map(\.id) == ["0", "1", "2"])
    }

    @Test("Starting a shuffled session retains the source ordering")
    func beginShuffledRetainsSource() throws {
        let songs = fixtures(4)
        var state = PlaybackQueueState()

        let shuffledSelection = state.beginShuffled(
            songs: songs,
            selecting: { $0[2] },
            shuffling: { Array($0.reversed()) }
        )
        let selected = try #require(shuffledSelection)

        #expect(selected == songs[2])
        #expect(state.originalItems == songs)
        #expect(state.items.map(\.id) == ["2", "3", "1", "0"])
    }

    private func fixtures(_ count: Int) -> [Song] {
        (0..<count).map { index in
            Song(
                id: String(index),
                title: "Song \(index)",
                duration: 180,
                absolutePath: nil,
                cloudflareID: nil,
                coverArt: nil,
                originalArtists: ["Artist"],
                coverArtists: nil,
                userUploaded: false
            )
        }
    }
}
