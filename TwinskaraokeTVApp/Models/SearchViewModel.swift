import Foundation
import Observation
struct TVSearchResult: Identifiable {
    let item: SearchSongItem
    let song: Song?
    var id: String { item.id }
}

@MainActor
@Observable
final class SearchViewModel {
    var results: [SearchSongItem] = [] {
        didSet {
            resolvedResults = results.map { TVSearchResult(item: $0, song: $0.toSong()) }
            playableSongs = resolvedResults.compactMap(\.song)
        }
    }
    private(set) var resolvedResults: [TVSearchResult] = []
    private(set) var playableSongs: [Song] = []
    var isLoading = false
    var searchText = "" {
        didSet { scheduleSearch() }
    }

    var loadError: String?

    @ObservationIgnored private var queryToken = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastDispatchedQuery = ""
    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != lastDispatchedQuery else { return }
        // Invalidate immediately: the previous response must not appear under
        // the new query while its debounce is pending.
        clearSearch()
        lastDispatchedQuery = ""
        guard !query.isEmpty else { return }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            lastDispatchedQuery = query
            performSearch(query: query)
        }
    }

    func performSearch(query: String) {
        searchTask?.cancel()
        queryToken &+= 1
        let token = queryToken
        isLoading = true
        loadError = nil
        searchTask = Task { [weak self] in
            do {
                let items = try await KaraokeAPIClient.searchSongItems(query: query, pageSize: 40)
                try Task.checkCancellation()
                guard let self, self.queryToken == token else { return }
                self.results = items
                self.finishSearch(token: token)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.queryToken == token else { return }
                self.results = []
                self.loadError = String(localized: "Check your connection and try again.")
                self.finishSearch(token: token)
            }
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        queryToken &+= 1
        results = []
        isLoading = false
        loadError = nil
    }

    private func finishSearch(token: Int) {
        guard queryToken == token else { return }
        searchTask = nil
        isLoading = false
    }

    deinit {
        searchDebounceTask?.cancel()
        searchTask?.cancel()
    }
}
