import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Playlist list search")
struct PlaylistListSearchTests {
    private func playlist(_ id: String, _ name: String) -> Playlist {
        Playlist(id: id, name: name, songCount: 0, mosaicMedia: nil, songListDTOs: nil)
    }

    @Test("Playlists past the loaded pages are found through the list's own URL")
    func searchUsesListURL() async throws {
        var requested: [URL] = []
        let loader = PlaylistListLoader(readToken: { nil }) { request in
            requested.append(try #require(request.url))
            return Data(#"[{"id":"far","name":"Evil Setlist"},{"id":"loose","name":"Unrelated"}]"#.utf8)
        }
        let loaded = [playlist("near", "Evil Mix"), playlist("other", "Other")]
        loader.bootstrap(initial: loaded) { start, size in
            "https://example.com/api/playlists?startIndex=\(start)&pageSize=\(size)&search=&isSetlist=True"
        }

        #expect(loader.matches(for: "evil", in: loaded).map(\.id) == ["near"])

        await loader.search("evil")
        let url = try #require(requested.first)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.filter { $0.name == "search" }.map(\.value) == ["evil"])
        // The list's other filters survive.
        #expect(items.contains(URLQueryItem(name: "isSetlist", value: "True")))
        #expect(!loader.isSearching)
        // Loose server matches are dropped; loaded matches keep their place.
        #expect(loader.matches(for: "evil", in: loaded).map(\.id) == ["near", "far"])
    }

    @Test("Lists handed every playlist up front search locally")
    func searchWithoutURLStaysLocal() async {
        var requests = 0
        let loader = PlaylistListLoader(readToken: { nil }) { _ in
            requests += 1
            return Data("[]".utf8)
        }
        await loader.search("evil")
        #expect(requests == 0)
        #expect(!loader.isSearching)
        #expect(loader.matches(for: "evil", in: [playlist("a", "Evil")]).map(\.id) == ["a"])
    }

    @Test("A superseded search does not commit")
    func cancelledSearch() async {
        let loader = PlaylistListLoader(readToken: { nil }) { _ in
            Data(#"[{"id":"far","name":"Evil Setlist"}]"#.utf8)
        }
        loader.bootstrap(initial: []) { _, _ in "https://example.com/api/playlists?search=" }
        let task = Task { await loader.search("evil") }
        task.cancel()
        await task.value
        #expect(loader.searchResults.isEmpty)
        #expect(loader.matches(for: "evil", in: []).isEmpty)
    }
}
