import Testing
@testable import Twinskaraoke_Watch_App

private actor SearchOwnershipLoader {
    private var continuations: [String: [CheckedContinuation<[SearchSongItem], Error>]] = [:]
    private var requestCounts: [String: Int] = [:]

    func load(query: String) async throws -> [SearchSongItem] {
        requestCounts[query, default: 0] += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[query, default: []].append(continuation)
        }
    }

    func waitUntilRequested(_ query: String, count: Int = 1) async -> Bool {
        for _ in 0 ..< 200 {
            if requestCounts[query, default: 0] >= count {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    func succeed(_ query: String, with items: [SearchSongItem]) {
        guard var pending = continuations[query], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        continuations[query] = pending
        continuation.resume(returning: items)
    }
}

@MainActor
@Suite("Watch search request ownership")
struct WatchSearchOwnershipTests {
    @Test("Editing the query invalidates the active request before debounce")
    func editingQueryImmediatelyRejectsStaleCompletion() async {
        let loader = SearchOwnershipLoader()
        let viewModel = SearchViewModel { query, _ in
            try await loader.load(query: query)
        }

        viewModel.searchText = "first"
        #expect(await loader.waitUntilRequested("first"))

        viewModel.searchText = "second"
        #expect(viewModel.isLoading)
        #expect(viewModel.results.isEmpty)

        await loader.succeed(
            "first",
            with: [makeSearchItem(id: "stale", title: "Stale Result")]
        )
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        #expect(viewModel.isLoading)
        #expect(viewModel.results.isEmpty)
        #expect(await loader.waitUntilRequested("second"))

        await loader.succeed(
            "second",
            with: [makeSearchItem(id: "current", title: "Current Result")]
        )
        for _ in 0 ..< 100 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(!viewModel.isLoading)
        #expect(viewModel.results.map(\.id) == ["current"])
    }

    @Test("Clearing text immediately rejects the active completion")
    func clearingTextImmediatelyRejectsActiveCompletion() async {
        let loader = SearchOwnershipLoader()
        let viewModel = SearchViewModel { query, _ in
            try await loader.load(query: query)
        }

        viewModel.searchText = "active"
        #expect(await loader.waitUntilRequested("active"))

        viewModel.searchText = ""
        #expect(!viewModel.isLoading)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.searchErrorMessage == nil)

        await loader.succeed(
            "active",
            with: [makeSearchItem(id: "late", title: "Late Result")]
        )
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        #expect(!viewModel.isLoading)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.searchErrorMessage == nil)
    }

    @Test("Returning to the last requested query starts a fresh request")
    func returningToLastQueryReloads() async {
        let loader = SearchOwnershipLoader()
        let viewModel = SearchViewModel { query, _ in
            try await loader.load(query: query)
        }

        viewModel.searchText = "repeat"
        #expect(await loader.waitUntilRequested("repeat"))

        viewModel.searchText = "temporary"
        viewModel.searchText = "repeat"
        await loader.succeed(
            "repeat",
            with: [makeSearchItem(id: "old", title: "Old Result")]
        )

        #expect(await loader.waitUntilRequested("repeat", count: 2))
        await loader.succeed(
            "repeat",
            with: [makeSearchItem(id: "fresh", title: "Fresh Result")]
        )
        for _ in 0 ..< 100 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(!viewModel.isLoading)
        #expect(viewModel.results.map(\.id) == ["fresh"])
    }

    private func makeSearchItem(id: String, title: String) -> SearchSongItem {
        SearchSongItem(
            id: id,
            title: title,
            duration: 180,
            absolutePath: "/audio/\(id).mp3",
            originalArtists: ["Original"],
            coverArtists: ["Cover"],
            coverArt: nil,
            cloudflareId: nil
        )
    }
}
