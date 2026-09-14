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
        var response: CheckedContinuation<[Song], Never>?
        let model = SearchViewModel(loadSongs: { _ in
            await withCheckedContinuation { response = $0 }
        })
        model.search("old")
        while response == nil { await Task.yield() }
        model.searchText = "new"
        response?.resume(returning: [UITestFixtures.song(id: "old", title: "Old", artist: "Artist")])
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
        let model = SearchViewModel(loadSongs: { query in
            queries.append(query)
            return []
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
        let model = SearchViewModel(loadSongs: { query in
            queries.append(query)
            return [UITestFixtures.song(id: "result", title: "Result", artist: "Artist")]
        })
        model.searchText = "Neu"
        model.searchText = "Neuro"
        #expect(model.isSearching)
        try await waitForSearchCompletion(model)
        #expect(queries == ["Neuro"])
        #expect(model.results.count == 1)
        #expect(!model.isSearching)
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
