import Foundation
import Observation

@Observable
final class PlaylistListLoader {
    var playlists: [Playlist] = []
    var isLoadingMore = false
    private var canLoadMore = true
    private let pageSize = 25
    private var urlBuilder: ((Int, Int) -> String)?

    func bootstrap(initial: [Playlist], urlBuilder: @escaping (Int, Int) -> String) {
        // Re-bootstrap when the view opened before page 1 arrived: the loader
        // is still empty and loadMoreIfNeeded can't fire on an empty list.
        guard self.urlBuilder == nil || (playlists.isEmpty && !initial.isEmpty) else { return }
        self.urlBuilder = urlBuilder
        playlists = initial
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
        let startIndex = playlists.count
        let urlString = urlBuilder(startIndex, pageSize)
        guard let url = URL(string: urlString) else {
            isLoadingMore = false
            return
        }
        var request = URLRequest(url: url)
        if let token = CredentialStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        GuestIdentity.applyIfNeeded(to: &request)
        // Routed through KaraokeAPIClient.data so 401s trigger the
        // session-expired flow and transient failures get retried.
        Task { [weak self] in
            let data = try? await KaraokeAPIClient.data(for: request)
            DispatchQueue.main.async {
                guard let self else { return }
                // A nil response is a transient failure — keep canLoadMore so
                // the next cell onAppear retries instead of disabling pagination.
                guard let data else {
                    self.isLoadingMore = false
                    return
                }
                let items = Self.decode(data: data)
                // An undecodable payload is a server-side anomaly, not the
                // last page — keep canLoadMore so scrolling retries.
                guard let items else {
                    self.isLoadingMore = false
                    return
                }
                if !items.isEmpty {
                    let existing = Set(self.playlists.map(\.id))
                    self.playlists += items.filter { !existing.contains($0.id) }
                    ArtworkPrefetcher.shared.prefetchPlaylists(
                        Array(items.prefix(12)),
                        limit: 12,
                        reason: "playlist list page"
                    )
                    self.canLoadMore = items.count >= self.pageSize
                } else {
                    self.canLoadMore = false
                }
                self.isLoadingMore = false
            }
        }
    }

    /// Returns nil when the payload matches no known shape; a genuinely
    /// empty page decodes fine as an empty array.
    private static func decode(data: Data) -> [Playlist]? {
        let decoder = JSONDecoder()
        if let items = (try? decoder.decode(LossyArray<PlaylistListItem>.self, from: data))?.elements {
            return items.map { $0.asPlaylist() }
        }
        if let items = try? decoder.decode([PlaylistListItem].self, from: data) {
            return items.map { $0.asPlaylist() }
        }
        return nil
    }
}
