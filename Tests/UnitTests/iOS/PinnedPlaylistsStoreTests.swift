import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Pinned playlists")
struct PinnedPlaylistsStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "PinnedPlaylistsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func playlist(_ id: String, songs: Int = 3) -> Playlist {
        let songs = (0 ..< songs).map { UITestFixtures.song(id: "\(id)-\($0)", title: "Song \($0)", artist: "Artist") }
        return UITestFixtures.playlist(id: id, name: "Playlist \(id)", songs: songs)
    }

    @Test("Pins keep the order they were pinned in, once each")
    func pinOrdersAndDeduplicates() {
        let store = PinnedPlaylistsStore(defaults: makeDefaults(), accountID: "user")
        store.pin(playlist("a"))
        store.pin(playlist("b"))
        store.pin(playlist("a"))
        #expect(store.playlists.map(\.id) == ["a", "b"])
        #expect(store.isPinned(playlist("b")))
        #expect(!store.isPinned(playlist("c")))
    }

    @Test("A seventh pin is refused rather than displacing one")
    func pinLimit() {
        let store = PinnedPlaylistsStore(defaults: makeDefaults(), accountID: "user")
        for index in 0 ..< PinnedPlaylistsStore.limit {
            store.pin(playlist("\(index)"))
        }
        #expect(store.isFull)
        store.pin(playlist("extra"))
        #expect(store.playlists.count == PinnedPlaylistsStore.limit)
        #expect(!store.isPinned(playlist("extra")))

        store.unpin(playlist("0"))
        #expect(!store.isFull)
        store.pin(playlist("extra"))
        #expect(store.playlists.last?.id == "extra")
    }

    @Test("Pins store metadata, not the playlist's songs")
    func pinStripsSongs() {
        let store = PinnedPlaylistsStore(defaults: makeDefaults(), accountID: "user")
        store.pin(playlist("a", songs: 40))
        #expect(store.playlists.first?.songListDTOs == nil)
        #expect(store.playlists.first?.name == "Playlist a")
        #expect(store.playlists.first?.songCount == 40)
    }

    @Test("Pins and unpins survive a relaunch")
    func persistence() {
        let defaults = makeDefaults()
        let first = PinnedPlaylistsStore(defaults: defaults, accountID: "user")
        first.pin(playlist("a"))
        first.pin(playlist("b"))
        first.unpin(playlist("a"))

        let relaunched = PinnedPlaylistsStore(defaults: defaults, accountID: "user")
        #expect(relaunched.playlists.map(\.id) == ["b"])
    }

    @Test("Each account keeps its own pins, and signing back in restores them")
    func pinsArePerAccount() {
        let defaults = makeDefaults()
        let store = PinnedPlaylistsStore(defaults: defaults, accountID: "alice")
        store.pin(playlist("a"))

        store.switchAccount(to: nil)
        #expect(store.playlists.isEmpty)
        store.pin(playlist("signed-out"))

        store.switchAccount(to: "bob")
        #expect(store.playlists.isEmpty)

        store.switchAccount(to: "alice")
        #expect(store.playlists.map(\.id) == ["a"])
        store.switchAccount(to: nil)
        #expect(store.playlists.map(\.id) == ["signed-out"])
    }

    @Test("Without storage, pins last only as long as the store")
    func volatileStore() {
        let store = PinnedPlaylistsStore(defaults: nil, accountID: "user")
        store.pin(playlist("a"))
        #expect(store.playlists.map(\.id) == ["a"])
        #expect(PinnedPlaylistsStore(defaults: nil, accountID: "user").playlists.isEmpty)
    }
}
