import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var results: [SearchSongItem] = []
    @Published var isLoading = false
    @Published var searchText = ""
    private var cancellables = Set<AnyCancellable>()
    private var queryToken = 0

    init() {
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                if !text.isEmpty {
                    self?.performSearch(query: text)
                } else {
                    self?.queryToken += 1
                    self?.results = []
                    self?.isLoading = false
                }
            }
            .store(in: &cancellables)
    }

    func performSearch(query: String) {
        queryToken += 1
        let token = queryToken
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let items = try await KaraokeAPIClient.searchSongItems(query: query, pageSize: 20)
                guard queryToken == token else { return }
                results = items
            } catch {
                guard queryToken == token else { return }
                results = []
            }
        }
    }
}
