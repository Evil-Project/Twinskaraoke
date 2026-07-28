import Combine
import Foundation

/// A search result paired with its playable Song, resolved once per results
/// change so rows don't re-run `toSong()` on every body evaluation.
struct TVSearchResult: Identifiable {
    let item: SearchSongItem
    let song: Song?
    var id: String { item.id }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var results: [SearchSongItem] = [] {
        didSet {
            resolvedResults = results.map { TVSearchResult(item: $0, song: $0.toSong()) }
            playableSongs = resolvedResults.compactMap(\.song)
        }
    }
    @Published private(set) var resolvedResults: [TVSearchResult] = []
    @Published private(set) var playableSongs: [Song] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var loadError: String?

    private var cancellables = Set<AnyCancellable>()
    private var queryToken = 0

    init() {
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                if !text.isEmpty {
                    self?.performSearch(query: text)
                } else {
                    self?.queryToken += 1
                    self?.results = []
                    self?.isLoading = false
                    self?.loadError = nil
                }
            }
            .store(in: &cancellables)
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
