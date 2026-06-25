import Combine
import Foundation

@MainActor
final class ArtistsViewModel: ObservableObject {
    @Published var artists: [Artist] = []
    @Published var isLoading = false
    @Published var canLoadMore = true
    private var page = 0
    private let pageSize = 25
    func fetchInitial() {
        guard artists.isEmpty else { return }
        page = 0
        canLoadMore = true
        load(reset: true)
    }

    func refresh() {
        page = 0
        canLoadMore = true
        load(reset: true)
    }

    func loadMoreIfNeeded(current: Artist) {
        guard let idx = artists.firstIndex(of: current) else { return }
        if idx >= artists.count - 5, !isLoading, canLoadMore {
            load(reset: false)
        }
    }

    private func load(reset: Bool) {
        let startIndex = page * pageSize
        let urlString =
            "\(StorageHost.api)/api/artists?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=Name&sortDescending=False"
        guard let url = URL(string: urlString) else { return }
        isLoading = true
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            Task { @MainActor [weak self, data, reset] in
                self?.applyArtistsResponse(data, reset: reset)
            }
        }.resume()
    }

    private func applyArtistsResponse(_ data: Data?, reset: Bool) {
        defer { isLoading = false }

        guard let data, let decoded = try? JSONDecoder().decode([Artist].self, from: data) else {
            return
        }

        if reset {
            artists = decoded
        } else {
            let existing = Set(artists.map(\.id))
            artists += decoded.filter { !existing.contains($0.id) }
        }
        page += 1
        canLoadMore = decoded.count == pageSize
    }
}

@MainActor
final class ArtistDetailViewModel: ObservableObject {
    @Published var artist: Artist?
    @Published var isLoading = false
    @Published private(set) var hasLoadedDetail = false
    @Published var errorMessage: String?
    private var loadedID: String?

    func load(id: String, fallback: Artist?, force: Bool = false) {
        if !force, loadedID == id, hasLoadedDetail { return }
        if artist == nil || loadedID != id { artist = fallback }
        loadedID = id
        hasLoadedDetail = false
        errorMessage = nil
        guard let url = URL(string: "\(StorageHost.api)/api/artist/\(id)") else { return }
        isLoading = true
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            Task { @MainActor [weak self, data] in
                self?.applyArtistDetailResponse(data)
            }
        }.resume()
    }

    private func applyArtistDetailResponse(_ data: Data?) {
        defer { isLoading = false }

        guard let data else {
            errorMessage = "Check your connection and try again."
            return
        }

        guard let decoded = try? JSONDecoder().decode(Artist.self, from: data) else {
            errorMessage = "The artist could not be loaded right now."
            return
        }

        artist = decoded
        hasLoadedDetail = true
        errorMessage = nil
    }
}
