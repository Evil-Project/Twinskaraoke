import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Library catalog search")
struct LibraryCatalogSearchTests {
    private func artist(_ id: String, _ name: String, summary: String? = nil) -> Artist {
        Artist(id: id, name: name, summary: summary, imagePath: nil, songCount: 1, songListDTOs: nil)
    }

    private func song(_ id: String, _ title: String, artist: String = "Artist") -> Song {
        UITestFixtures.song(id: id, title: title, artist: artist)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Condition not met within five seconds")
    }

    @Test("Artists past the loaded pages are found through the server")
    func artistsSearchServer() async {
        var queries: [String] = []
        let model = ArtistsViewModel(searchArtists: { query in
            queries.append(query)
            // Loose server matching, as the real endpoint does.
            return [self.artist("joji", "Joji"), self.artist("tdg", "Three Days Grace")]
        })
        model.artists = [artist("abba", "ABBA"), artist("a-joji-fan", "A Joji Fan")]

        // Loaded matches show immediately, before the server answers.
        #expect(model.matches(for: "joji").map(\.id) == ["a-joji-fan"])

        await model.search("joji")
        #expect(queries == ["joji"])
        #expect(!model.isSearching)
        // The server's loose match is dropped; results are merged in name order.
        #expect(model.matches(for: "joji").map(\.id) == ["a-joji-fan", "joji"])
        // A different query does not reuse these results.
        #expect(model.matches(for: "abba").map(\.id) == ["abba"])
    }

    @Test("A superseded artist search does not commit")
    func artistsSearchCancellation() async throws {
        var reply: CheckedContinuation<[Artist], Never>?
        let model = ArtistsViewModel(searchArtists: { _ in
            await withCheckedContinuation { reply = $0 }
        })
        let task = Task { await model.search("joji") }
        // Cancel only once the request is actually in flight.
        try await waitUntil { reply != nil }
        task.cancel()
        reply?.resume(returning: [artist("joji", "Joji")])
        await task.value
        #expect(model.searchResults.isEmpty)
        #expect(model.matches(for: "joji").isEmpty)

        await model.search("")
        #expect(!model.isSearching)
        #expect(model.searchedQuery.isEmpty)
    }

    @Test("Library songs search reaches songs that are not loaded yet")
    func songsSearchServer() async throws {
        // Fixture artists read "… · Cover by Neuro", so the query avoids that.
        let model = LibrarySongsViewModel(searchSongs: { _ in
            [self.song("remote", "Send Me an Angel"), self.song("local", "Angel Song")]
        })
        model.songs = [song("local", "Angel Song"), song("other", "Other")]
        model.searchText = "angel"
        try await waitUntil { model.displayedSongs.count == 2 && !model.isSearchingRemotely }
        // Local matches first, the server's extras after, no duplicates.
        #expect(model.displayedSongs.map(\.id) == ["local", "remote"])

        model.sort = .title
        #expect(model.displayedSongs.map(\.id) == ["local", "remote"])

        model.searchText = ""
        try await waitUntil { model.displayedSongs.contains { $0.id == "other" } }
        #expect(Set(model.displayedSongs.map(\.id)) == ["local", "other"])
    }

    @Test("A hanging song search does not keep the view model alive")
    func songsSearchDoesNotRetainModel() async throws {
        var started = false
        weak var released: LibrarySongsViewModel?
        do {
            let model = LibrarySongsViewModel(searchSongs: { _ in
                started = true
                try await Task.sleep(for: .seconds(60))
                return []
            })
            released = model
            model.searchText = "angel"
            try await waitUntil { started }
        }
        try await waitUntil { released == nil }
    }

    @Test("A failed server search still shows the loaded matches")
    func songsSearchFailure() async throws {
        let model = LibrarySongsViewModel(searchSongs: { _ in throw URLError(.notConnectedToInternet) })
        model.songs = [song("local", "Angel Song"), song("other", "Other")]
        model.searchText = "angel"
        try await waitUntil { !model.isSearchingRemotely && model.displayedSongs.count == 1 }
        #expect(model.displayedSongs.map(\.id) == ["local"])
    }
}
