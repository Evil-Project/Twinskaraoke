import Foundation
import Observation

@MainActor
@Observable
final class PlaylistListLoader {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoadingMore = false
    private var canLoadMore = true
    private let pageSize = 25
    private var nextOffset = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let fetchData: @MainActor (URLRequest) async throws -> Data

    @ObservationIgnored private let readToken: () throws -> String?

    init(readToken: @escaping () throws -> String? = CredentialStore.requestToken, fetchData: @escaping @MainActor (URLRequest) async throws -> Data = {
        try await KaraokeAPIClient.data(for: $0)
    }) {
        self.readToken = readToken
        self.fetchData = fetchData
    }

    deinit { loadTask?.cancel() }

    private var urlBuilder: ((Int, Int) -> String)?

    /// Server matches for `searchedQuery`. `playlists` holds only the pages
    /// scrolled into view, so filtering it alone could not find a playlist
    /// further down the list, and said No Results.
    private(set) var searchResults: [Playlist] = []
    private(set) var searchedQuery = ""
    private(set) var isSearching = false

    /// Loaded playlists matching `query` straight away, then the server's
    /// matches once they arrive, without duplicates.
    func matches(for query: String, in loaded: [Playlist]) -> [Playlist] {
        let local = loaded.filter { $0.name.localizedCaseInsensitiveContains(query) }
        guard searchedQuery == query else { return local }
        var seen = Set(local.map(\.id))
        return local + searchResults.filter { seen.insert($0.id).inserted }
    }

    /// Runs from the view's `task(id:)`, which cancels it when the query
    /// changes; that is also the debounce. Lists without a server URL (the
    /// ones handed every playlist up front) stay local.
    func search(_ query: String) async {
        guard !query.isEmpty, let url = searchURL(for: query) else {
            searchedQuery = ""
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(300))
            var request = URLRequest(url: url)
            if let token = try readToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            GuestIdentity.applyIfNeeded(to: &request)
            let data = try await fetchData(request)
            try Task.checkCancellation()
            let page = try JSONDecoder().decode(LossyArray<PlaylistListItem>.self, from: data)
            searchResults = page.elements.map { $0.asPlaylist() }
                .filter { $0.name.localizedCaseInsensitiveContains(query) }
            searchedQuery = query
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchedQuery = query
            isSearching = false
        }
    }

    /// The list's own page URL with its `search` item set. Both builders in use
    /// already carry an empty one; replacing it keeps their other parameters,
    /// such as the setlist filter.
    private func searchURL(for query: String) -> URL? {
        guard let urlBuilder, var components = URLComponents(string: urlBuilder(0, 50)) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "search" }
        items.append(URLQueryItem(name: "search", value: query))
        components.queryItems = items
        return components.url
    }

    func bootstrap(initial: [Playlist], urlBuilder: @escaping (Int, Int) -> String) {
        // Re-bootstrap when the view opened before page 1 arrived: the loader
        // is still empty and loadMoreIfNeeded can't fire on an empty list.
        guard self.urlBuilder == nil || (playlists.isEmpty && !initial.isEmpty) else { return }
        self.urlBuilder = urlBuilder
        var seen = Set<String>()
        playlists = initial.filter { seen.insert($0.id).inserted }
        nextOffset = initial.count
        canLoadMore = true
    }

    func loadMoreIfNeeded(current: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == current.id }) else { return }
        if idx >= playlists.count - 4, !isLoadingMore, canLoadMore {
            loadMore()
        }
    }

    private func loadMore() {
        guard let urlBuilder else { return }
        isLoadingMore = true
        let startIndex = nextOffset
        let urlString = urlBuilder(startIndex, pageSize)
        guard let url = URL(string: urlString) else {
            isLoadingMore = false
            return
        }
        // Routed through KaraokeAPIClient.data so 401s trigger the
        // session-expired flow and transient failures get retried.
        let fetchData = self.fetchData
        let readToken = self.readToken
        loadTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                if let token = try readToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                GuestIdentity.applyIfNeeded(to: &request)
                let data = try await fetchData(request)
                try Task.checkCancellation()
                guard let self else { return }
                defer {
                    isLoadingMore = false
                    loadTask = nil
                }
                // Malformed top-level responses must not disable retries.
                let page = try JSONDecoder().decode(LossyArray<PlaylistListItem>.self, from: data)
                let items = page.elements.map { $0.asPlaylist() }
                nextOffset = startIndex + page.sourceCount
                var existing = Set(playlists.map(\.id))
                playlists += items.filter { existing.insert($0.id).inserted }
                canLoadMore = page.sourceCount >= pageSize
                ArtworkPrefetcher.shared.prefetchPlaylists(
                    Array(items.prefix(12)),
                    limit: 12,
                    reason: "playlist list page"
                )
            } catch {
                self?.isLoadingMore = false
                self?.loadTask = nil
            }
        }
    }
}
