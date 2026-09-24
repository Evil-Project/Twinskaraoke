import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Recent searches")
struct RecentSearchesStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "RecentSearchesStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func song(_ id: String) -> Song {
        UITestFixtures.song(id: id, title: "Song \(id)", artist: "Artist")
    }

    @Test("Newest pick comes first and a repeat moves instead of duplicating")
    func recordOrdersAndDeduplicates() {
        let store = RecentSearchesStore(defaults: makeDefaults())
        store.record(song("a"))
        store.record(song("b"))
        store.record(song("a"))
        #expect(store.songs.map(\.id) == ["a", "b"])
    }

    @Test("The list is capped, dropping the oldest")
    func recordCaps() {
        let store = RecentSearchesStore(defaults: makeDefaults())
        for index in 0 ..< RecentSearchesStore.limit + 3 {
            store.record(song("\(index)"))
        }
        #expect(store.songs.count == RecentSearchesStore.limit)
        #expect(store.songs.first?.id == "\(RecentSearchesStore.limit + 2)")
        #expect(!store.songs.contains { $0.id == "0" })
    }

    @Test("Picks survive a relaunch; removing and clearing persist too")
    func persistence() {
        let defaults = makeDefaults()
        let first = RecentSearchesStore(defaults: defaults)
        first.record(song("a"))
        first.record(song("b"))
        first.record(song("c"))

        let relaunched = RecentSearchesStore(defaults: defaults)
        #expect(relaunched.songs.map(\.id) == ["c", "b", "a"])
        #expect(relaunched.songs.first?.title == "Song c")

        relaunched.remove(song("b"))
        #expect(RecentSearchesStore(defaults: defaults).songs.map(\.id) == ["c", "a"])

        relaunched.clear()
        #expect(relaunched.songs.isEmpty)
        #expect(RecentSearchesStore(defaults: defaults).songs.isEmpty)
    }
}
