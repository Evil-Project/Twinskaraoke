import Foundation
import Testing
@testable import Twinskaraoke

private actor ControlledSongSearchLoader {
    typealias Continuation = CheckedContinuation<[Song], Error>

    private var requests: [(query: String, continuation: Continuation)] = []
    private var totalRequests = 0

    func load(query: String) async throws -> [Song] {
        try await withCheckedThrowingContinuation { continuation in
            totalRequests += 1
            requests.append((query, continuation))
        }
    }

    func waitUntilRequestCount(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
    }

    func succeed(query: String, songs: [Song]) {
        guard let index = requests.firstIndex(where: { $0.query == query }) else { return }
        let request = requests.remove(at: index)
        request.continuation.resume(returning: songs)
    }

    func totalRequestCount() -> Int {
        totalRequests
    }
}

@MainActor
@Suite("Search result ownership")
struct SearchViewModelTests {
    @Test("Editing the query invalidates an in-flight result before debounce fires")
    func queryEditImmediatelyInvalidatesOlderResult() async {
        let loader = ControlledSongSearchLoader()
        let viewModel = SearchViewModel(debounceInterval: .seconds(60)) { query, _ in
            try await loader.load(query: query)
        }

        viewModel.searchText = "alpha"
        let alphaTask = viewModel.search("alpha")
        await loader.waitUntilRequestCount(1)

        viewModel.searchText = "beta"
        await loader.succeed(query: "alpha", songs: [Self.song(id: "alpha")])
        await alphaTask?.value

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.isSearching)
        #expect(viewModel.searchErrorMessage == nil)
    }

    @Test("A late older completion cannot replace the latest query results")
    func latestQueryOwnsResults() async {
        let loader = ControlledSongSearchLoader()
        let viewModel = SearchViewModel(debounceInterval: .seconds(60)) { query, _ in
            try await loader.load(query: query)
        }

        viewModel.searchText = "alpha"
        let alphaTask = viewModel.search("alpha")
        await loader.waitUntilRequestCount(1)

        viewModel.searchText = "beta"
        let betaTask = viewModel.search("beta")
        await loader.waitUntilRequestCount(2)

        await loader.succeed(query: "beta", songs: [Self.song(id: "beta")])
        await betaTask?.value
        await loader.succeed(query: "alpha", songs: [Self.song(id: "alpha")])
        await alphaTask?.value

        #expect(viewModel.results.map(\.id) == ["beta"])
        #expect(!viewModel.isSearching)
    }

    @Test("Editing away and back inside the debounce window starts a fresh search")
    func editBackToSameQueryReloads() async throws {
        let loader = ControlledSongSearchLoader()
        let viewModel = SearchViewModel { query, _ in
            try await loader.load(query: query)
        }

        viewModel.searchText = "alpha"
        try await Task.sleep(for: .milliseconds(650))
        #expect(await loader.totalRequestCount() == 1)
        await loader.succeed(query: "alpha", songs: [Self.song(id: "first-alpha")])
        await waitUntilSearchFinishes(viewModel)

        viewModel.searchText = "beta"
        viewModel.searchText = "alpha"
        try await Task.sleep(for: .milliseconds(650))

        #expect(await loader.totalRequestCount() == 2)
        #expect(viewModel.isSearching)
        await loader.succeed(query: "alpha", songs: [Self.song(id: "second-alpha")])
        await waitUntilSearchFinishes(viewModel)

        #expect(viewModel.results.map(\.id) == ["second-alpha"])
        #expect(!viewModel.isSearching)
    }

    private static func song(id: String) -> Song {
        Song(
            id: id,
            title: id.capitalized,
            duration: 180,
            absolutePath: "audio/\(id).mp3",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: false
        )
    }

    private func waitUntilSearchFinishes(_ viewModel: SearchViewModel) async {
        while viewModel.isSearching {
            await Task.yield()
        }
    }
}
