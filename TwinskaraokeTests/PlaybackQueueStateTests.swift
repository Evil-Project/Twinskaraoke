import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Playback queue state")
struct PlaybackQueueStateTests {
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
