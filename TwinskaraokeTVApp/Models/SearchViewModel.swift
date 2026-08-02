import Foundation
import Observation

/// A search result paired with its playable Song, resolved once per results
/// change so rows don't re-run `toSong()` on every body evaluation.
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
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastDispatchedQuery = ""

    /// Replaces the former `$searchText.debounce().removeDuplicates()` pipeline:
    /// `@Observable` has no publisher projection, so the 400ms coalescing and
    /// the duplicate-query suppression are done here instead.
    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != lastDispatchedQuery else { return }
            lastDispatchedQuery = text
            if text.isEmpty {
                queryToken += 1
                results = []
                isLoading = false
                loadError = nil
            } else {
                performSearch(query: text)
            }
        }
    }

    func performSearch(query: String) {
        queryToken += 1
        let token = queryToken
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { if queryToken == token { isLoading = false } }
            do {
                let items = try await KaraokeAPIClient.searchSongItems(query: query, pageSize: 40)
                guard queryToken == token else { return }
                results = items
            } catch {
                guard queryToken == token else { return }
                results = []
                loadError = "Check your connection and try again."
            }
        }
    }
}
