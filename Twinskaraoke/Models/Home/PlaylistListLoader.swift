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
