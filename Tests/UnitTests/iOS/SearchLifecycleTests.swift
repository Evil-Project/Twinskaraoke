import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Search lifecycle")
struct SearchLifecycleTests {
    @Test("Editing a query clears results and errors before the debounce")
    func editingInvalidatesPresentationImmediately() {
        let model = SearchViewModel()
        model.results = [UITestFixtures.song(id: "old", title: "Old", artist: "Artist")]
        model.searchErrorMessage = "Old error"
        model.isSearching = true
        model.searchText = "new query"
        #expect(model.results.isEmpty)
        #expect(model.searchErrorMessage == nil)
        #expect(model.isSearching)
        model.searchText = ""
    }

    @Test("An old response is rejected during the next query's debounce")
    func lateResponseDuringDebounce() async {
        var response: CheckedContinuation<SongSearchPage, Never>?
        let model = SearchViewModel(loadPage: { _, _ in
            await withCheckedContinuation { response = $0 }
        })
        model.search("old")
        while response == nil { await Task.yield() }
        model.searchText = "new"
        response?.resume(returning: page([UITestFixtures.song(id: "old", title: "Old", artist: "Artist")]))
        for _ in 0..<10 { await Task.yield() }
        #expect(model.results.isEmpty)
        #expect(model.searchErrorMessage == nil)
        model.searchText = ""
    }

    @Test("Clearing a pending query cancels the search without waiting")
    func clearingPendingQuery() async throws {
        let model = SearchViewModel()
        model.searchText = "pending"
        model.searchText = "  \n"
        #expect(!model.hasActiveQuery)
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
        #expect(model.searchErrorMessage == nil)
    }

    @Test("Submitting immediately cancels the delayed duplicate request")
    func submittingPendingQuery() async throws {
        var queries: [String] = []
        let model = SearchViewModel(loadPage: { query, _ in
            queries.append(query)
            return page([])
        })
        model.searchText = "Neuro"
        #expect(model.isSearching)
        model.search(model.searchText)
        try await waitForSearchCompletion(model)
        #expect(queries == ["Neuro"])
        #expect(!model.isSearching)
        try await Task.sleep(for: .milliseconds(600))
        #expect(queries == ["Neuro"])
        model.searchText = "Neuro "
        #expect(!model.isSearching)
    }

    @Test("Typing coalesces into the latest query and then leaves loading")
    func typingDispatchesLatestQuery() async throws {
        var queries: [String] = []
        let model = SearchViewModel(loadPage: { query, _ in
            queries.append(query)
            return page([UITestFixtures.song(id: "result", title: "Result", artist: "Artist")])
        })
        model.searchText = "Neu"
        model.searchText = "Neuro"
        #expect(model.isSearching)
        try await waitForSearchCompletion(model)
        #expect(queries == ["Neuro"])
        #expect(model.results.count == 1)
        #expect(!model.isSearching)
    }

    @Test("Scrolling near the end loads the next page of the same query")
    func scrollingLoadsNextPage() async throws {
        var requests: [(String, Int)] = []
        let model = SearchViewModel(loadPage: { query, number in
            requests.append((query, number))
            return page(songs(number == 1 ? 0..<30 : 30..<60), total: 75)
        })
        model.search("Neuro")
        try await waitForSearchCompletion(model)
        #expect(model.results.count == 30)
        #expect(model.totalResultCount == 75)
        #expect(model.canLoadMore)

        // Far from the end: nothing to fetch yet.
        model.loadMoreIfNeeded(after: model.results[5])
        #expect(!model.isLoadingMore)

        model.loadMoreIfNeeded(after: model.results[25])
        try await waitUntil { !model.isLoadingMore }
        #expect(requests.map(\.1) == [1, 2])
        #expect(requests.allSatisfy { $0.0 == "Neuro" })
        #expect(model.results.map(\.id) == (0..<60).map { "song-\($0)" })
        #expect(model.canLoadMore)
    }

    @Test("Paging stops at the server total and on pages that add nothing")
    func pagingStops() async throws {
        let model = SearchViewModel(loadPage: { _, number in
            // The second page repeats the first, as a shifting index can.
            page(songs(0..<30), total: number == 1 ? 90 : nil)
        })
        model.search("Neuro")
        try await waitForSearchCompletion(model)
        #expect(model.canLoadMore)
        model.loadMoreIfNeeded(after: model.results[29])
        try await waitUntil { !model.isLoadingMore }
        #expect(model.results.count == 30)
        #expect(!model.canLoadMore)

        let complete = SearchViewModel(loadPage: { _, _ in page(songs(0..<12), total: 12) })
        complete.search("Short")
        try await waitForSearchCompletion(complete)
        #expect(!complete.canLoadMore)
    }

    @Test("A page arriving after the query changed is discarded")
    func stalePageIsDiscarded() async throws {
        var pending: CheckedContinuation<SongSearchPage, Never>?
        let model = SearchViewModel(loadPage: { query, number in
            if number == 1 {
                return page(songs(0..<30, prefix: query), total: 100)
            }
            return await withCheckedContinuation { pending = $0 }
        })
        model.search("old")
        try await waitForSearchCompletion(model)
        model.loadMoreIfNeeded(after: model.results[29])
        while pending == nil { await Task.yield() }

        model.search("new")
        try await waitForSearchCompletion(model)
        pending?.resume(returning: page(songs(30..<60, prefix: "old"), total: 100))
        for _ in 0..<10 { await Task.yield() }
        #expect(model.results.count == 30)
        #expect(model.results.allSatisfy { $0.id.hasPrefix("new") })
        #expect(!model.isLoadingMore)
    }

    @Test("A failed page can be retried")
    func failedPageRetries() async throws {
        var failNext = true
        let model = SearchViewModel(loadPage: { _, number in
            if number == 2, failNext {
                failNext = false
                throw URLError(.timedOut)
            }
            return page(songs(number == 1 ? 0..<30 : 30..<40), total: 40)
        })
        model.search("Neuro")
        try await waitForSearchCompletion(model)
        model.loadMoreIfNeeded(after: model.results[29])
        try await waitUntil { !model.isLoadingMore }
        #expect(model.loadMoreFailed)
        #expect(model.results.count == 30)

        // Scrolling again must not hammer a failing page; retry is explicit.
        model.loadMoreIfNeeded(after: model.results[29])
        #expect(!model.isLoadingMore)

        model.retryLoadMore()
        try await waitUntil { !model.isLoadingMore }
        #expect(!model.loadMoreFailed)
        #expect(model.results.count == 40)
        #expect(!model.canLoadMore)
    }

    private func page(_ songs: [Song], total: Int? = nil) -> SongSearchPage {
        SongSearchPage(songs: songs, totalCount: total)
    }

    private func songs(_ range: Range<Int>, prefix: String = "song") -> [Song] {
        range.map { UITestFixtures.song(id: "\(prefix)-\($0)", title: "Song \($0)", artist: "Artist") }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Condition not met within five seconds")
    }

    private func waitForSearchCompletion(_ model: SearchViewModel) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while model.isSearching, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!model.isSearching, "Search did not complete within five seconds")
    }
}


@Suite("Visible genre cache lifetime")
@MainActor
struct GenreCacheLifetimeTests {
    private var songs: [Song] {
        [UITestFixtures.song(id: "genre-song", title: "Song", artist: "Artist")]
    }

    @Test("Visible genre survives more than thirty later detail responses")
    func visibleGenreSurvivesEviction() {
        let model = GenresViewModel()
        let owner = UUID()
        model.retainDetail("visible", owner: owner)
        model.cacheDetailSongs(songs, for: "visible", retainFullDetail: true)
        for index in 0..<40 {
            model.cacheDetailSongs(songs, for: "other-\(index)", retainFullDetail: true)
        }
        #expect(model.allSongs["visible"] == songs)
        #expect(model.allSongs.count == 30)
        model.releaseDetail(owner: owner)
        model.cacheDetailSongs(songs, for: "new", retainFullDetail: true)
        #expect(model.allSongs["visible"] == nil)
    }

    @Test("Tile responses never retain their full detail arrays")
    func previewDoesNotPopulateDetailCache() {
        let model = GenresViewModel()
        for index in 0..<64 {
            model.cacheDetailSongs(songs, for: "preview-\(index)", retainFullDetail: false)
        }
        #expect(model.allSongs.isEmpty)
        #expect(model.firstSongs.count == 64)
    }

    @Test("Memory pressure preserves visible data and respects multiple owners")
    func memoryPressureKeepsVisibleLists() {
        let model = GenresViewModel()
        let first = UUID(), second = UUID()
        model.retainDetail("visible", owner: first)
        model.retainDetail("visible", owner: second)
        model.cacheDetailSongs(songs, for: "visible", retainFullDetail: true)
        model.cacheDetailSongs(songs, for: "background", retainFullDetail: true)
        model.releaseDetail(owner: first)
        let generation = model.detailGeneration
        model.clearCachedGenreDetails()
        #expect(model.detailGeneration != generation)
        #expect(model.allSongs["visible"] == songs)
        #expect(model.allSongs["background"] == nil)
        model.releaseDetail(owner: second)
        model.clearCachedGenreDetails()
        #expect(model.allSongs.isEmpty)
    }
}
