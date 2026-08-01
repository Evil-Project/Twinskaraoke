import Testing
@testable import Twinskaraoke_Watch_App

private actor RetryingWatchSearchLoader {
    enum Failure: Error {
        case simulated
    }

    private var attempts = 0

    func load(query: String) async throws -> [SearchSongItem] {
        attempts += 1
        if attempts == 1 {
            throw Failure.simulated
        }
        return [
            SearchSongItem(
                id: "retry-result",
                title: "Retry Result",
                duration: 180,
                absolutePath: "/audio/retry.mp3",
                originalArtists: ["Original"],
                coverArtists: ["Cover"],
                coverArt: nil,
                cloudflareId: nil
            )
        ]
    }

    func attemptCount() -> Int {
        attempts
    }
}

@MainActor
@Suite("Watch search retry")
struct WatchSearchRetryTests {
    @Test("Submitting a failed unchanged query starts a new request")
    func failedSameQueryCanBeSubmittedAgain() async {
        let loader = RetryingWatchSearchLoader()
        let viewModel = SearchViewModel { query, _ in
            try await loader.load(query: query)
        }

        viewModel.performSearch(query: "same query")
        for _ in 0 ..< 100 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(viewModel.searchErrorMessage != nil)
        #expect(await loader.attemptCount() == 1)

        viewModel.searchText = "same query"
        viewModel.submitSearch()
        for _ in 0 ..< 100 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(await loader.attemptCount() == 2)
        #expect(viewModel.searchErrorMessage == nil)
        #expect(viewModel.results.map(\.id) == ["retry-result"])
    }
}
