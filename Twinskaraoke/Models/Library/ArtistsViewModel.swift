import Combine
import Foundation

@MainActor
final class ArtistsViewModel: ObservableObject {
    @Published var artists: [Artist] = []
    @Published var isLoading = false
    @Published var canLoadMore = true
    @Published private(set) var loadFailed = false
    private var page = 0
    private let pageSize = 25
    private var loadGeneration = 0
    private var activeTask: URLSessionDataTask?
    func fetchInitial() {
        guard artists.isEmpty, !isLoading else { return }
        page = 0
        canLoadMore = true
        load(reset: true)
    }

    func refresh() {
        activeTask?.cancel()
        activeTask = nil
        loadGeneration += 1
        isLoading = false
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
        guard !isLoading else { return }
        let startIndex = page * pageSize
        let urlString =
            "\(StorageHost.api)/api/artists?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=Name&sortDescending=False"
        guard let url = URL(string: urlString) else { return }
        isLoading = true
        if reset {
            loadFailed = false
        }
        loadGeneration += 1
        let generation = loadGeneration
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self, data, response, error, reset, generation] in
                self?.applyArtistsResponse(
                    data,
                    response: response,
                    error: error,
                    reset: reset,
                    generation: generation
                )
            }
        }
        activeTask = task
        task.resume()
    }

    private func applyArtistsResponse(
        _ data: Data?,
        response: URLResponse?,
        error: Error?,
        reset: Bool,
        generation: Int
    ) {
        guard generation == loadGeneration else { return }
        defer {
            activeTask = nil
            isLoading = false
        }

        guard error == nil,
              (response as? HTTPURLResponse).map({ (200 ... 299).contains($0.statusCode) }) != false,
              let data,
              let decoded = try? JSONDecoder().decode([Artist].self, from: data)
        else {
            if reset, artists.isEmpty {
                loadFailed = true
            }
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

    deinit {
        activeTask?.cancel()
    }
}

@MainActor
final class ArtistDetailViewModel: ObservableObject {
    @Published var artist: Artist?
    @Published var isLoading = false
    @Published private(set) var hasLoadedDetail = false
    @Published var errorMessage: String?
    private var loadedID: String?
    private var loadGeneration = 0
    private var activeTask: URLSessionDataTask?

    func load(id: String, fallback: Artist?, force: Bool = false) {
        if !force, loadedID == id, hasLoadedDetail { return }
        if artist == nil || loadedID != id { artist = fallback }
        loadedID = id
        activeTask?.cancel()
        activeTask = nil
        loadGeneration += 1
        let generation = loadGeneration
        hasLoadedDetail = false
        errorMessage = nil
        guard let request = try? KaraokeAPIClient.request(
            pathSegments: ["api", "artist", id]
        ) else {
            isLoading = false
            errorMessage = "The artist could not be loaded right now."
            return
        }
        isLoading = true
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self, data, response, error, id, generation] in
                self?.applyArtistDetailResponse(
                    data,
                    response: response,
                    error: error,
                    id: id,
                    generation: generation
                )
            }
        }
        activeTask = task
        task.resume()
    }

    private func applyArtistDetailResponse(
        _ data: Data?,
        response: URLResponse?,
        error: Error?,
        id: String,
        generation: Int
    ) {
        guard loadedID == id, generation == loadGeneration else { return }
        defer {
            activeTask = nil
            isLoading = false
        }

        guard error == nil else {
            errorMessage = "Check your connection and try again."
            return
        }
        guard (response as? HTTPURLResponse).map({ (200 ... 299).contains($0.statusCode) }) != false,
              let data
        else {
            errorMessage = "The artist could not be loaded right now."
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

    deinit {
        activeTask?.cancel()
    }
}
