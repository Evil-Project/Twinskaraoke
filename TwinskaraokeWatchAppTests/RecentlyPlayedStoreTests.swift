import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

/// Serialized because these exercise the shared store, which persists to
/// `UserDefaults.standard` like the rest of the watch app.
@MainActor
@Suite("Watch recently played", .serialized)
struct RecentlyPlayedStoreTests {
    private func song(_ id: String) -> Song {
        UITestFixtures.song(id: id, title: "Song \(id)", artist: "Artist")
    }

    @Test("Most recent song comes first")
    func recordsNewestFirst() {
        let store = RecentlyPlayedStore.shared
        store.clear()

        store.record(song("a"))
        store.record(song("b"))

        #expect(store.songs.map(\.id) == ["b", "a"])
        store.clear()
    }

    @Test("Replaying a song moves it to the front instead of duplicating it")
    func replayDeduplicates() {
        let store = RecentlyPlayedStore.shared
        store.clear()

        store.record(song("a"))
        store.record(song("b"))
        store.record(song("a"))

        #expect(store.songs.map(\.id) == ["a", "b"])
        store.clear()
    }

    /// The list is meant to stay a glance on a watch screen, and it is
    /// re-encoded on every track change.
    @Test("History is capped and drops the oldest entries")
    func historyIsCapped() {
        let store = RecentlyPlayedStore.shared
        store.clear()

        for index in 0 ..< 14 {
            store.record(song("song-\(index)"))
        }

        #expect(store.songs.count == 10)
        #expect(store.songs.first?.id == "song-13")
        #expect(store.songs.last?.id == "song-4")
        store.clear()
    }

    @Test("Clearing empties the list")
    func clearEmptiesHistory() {
        let store = RecentlyPlayedStore.shared
        store.record(song("a"))

        store.clear()

        #expect(store.songs.isEmpty)
    }
}
