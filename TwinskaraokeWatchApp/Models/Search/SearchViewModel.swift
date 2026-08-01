import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    typealias SearchLoader = @Sendable (_ query: String, _ pageSize: Int) async throws -> [SearchSongItem]

    @Published var results: [SearchSongItem] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published private(set) var searchErrorMessage: String?
    private var cancellables = Set<AnyCancellable>()
    private var queryToken = 0
    private var lastRequestedQuery = ""
    private var searchTask: Task<Void, Never>?
    private let searchLoader: SearchLoader

    init(
        searchLoader: @escaping SearchLoader = { query, pageSize in
            try await KaraokeAPIClient.searchSongItems(query: query, pageSize: pageSize)
        }
    ) {
        self.searchLoader = searchLoader
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] text in
                self?.prepareForSearchTextChange(text)
            })
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard !text.isEmpty else { return }
                self?.performSearch(query: text)
            }
            .store(in: &cancellables)
    }

    func submitSearch() {
        performSearch(query: searchText)
    }

    func retrySearch() {
        performSearch(query: searchText, force: true)
    }

    func performSearch(query: String, force: Bool = false) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearch()
            return
        }
        let retryingFailedQuery = searchErrorMessage != nil && trimmedQuery == lastRequestedQuery
        guard force || retryingFailedQuery || trimmedQuery != lastRequestedQuery else { return }

        queryToken += 1
        let token = queryToken
        lastRequestedQuery = trimmedQuery
        searchTask?.cancel()
        results = []
        isLoading = true
        searchErrorMessage = nil
        let searchLoader = searchLoader
        searchTask = Task { [weak self] in
            do {
                let items = try await searchLoader(trimmedQuery, 20)
                guard let self else { return }
                guard queryToken == token, !Task.isCancelled else { return }
                results = items
                isLoading = false
                searchTask = nil
            } catch {
                guard let self else { return }
                guard queryToken == token, !Task.isCancelled else { return }
                results = []
                isLoading = false
                searchErrorMessage = "Search is temporarily unavailable. Check your connection and try again."
                searchTask = nil
            }
        }
    }

    private func clearSearch() {
        prepareForSearchTextChange("")
    }

    private func prepareForSearchTextChange(_ query: String) {
        queryToken += 1
        lastRequestedQuery = ""
        searchTask?.cancel()
        searchTask = nil
        results = []
        isLoading = !query.isEmpty
        searchErrorMessage = nil
    }
}
