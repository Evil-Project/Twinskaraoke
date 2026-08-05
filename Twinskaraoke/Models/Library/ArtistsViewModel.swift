import Foundation
import Observation

@MainActor
@Observable
final class ArtistsViewModel {
    var artists: [Artist] = []
    var isLoading = false
    var canLoadMore = true
    private(set) var loadFailed = false
    private var page = 0
    private let pageSize = 25
    private var loadGeneration = 0
    @ObservationIgnored private var activeTask: Task<Void, Never>?
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

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the artists have actually finished loading. Deliberately not an
    /// `async` overload of `refresh()` — in an async context Swift would
    /// prefer the async overload and recurse.
    func refreshArtists() async {
        refresh()
        await activeTask?.value
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
        guard let request = try? KaraokeAPIClient.request(
            path: "/api/artists",
            queryItems: [
                URLQueryItem(name: "startIndex", value: String(startIndex)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
                URLQueryItem(name: "search", value: ""),
                URLQueryItem(name: "sortBy", value: "Name"),
                URLQueryItem(name: "sortDescending", value: "False"),
            ]
        ) else { return }
        isLoading = true
        if reset {
            loadFailed = false
        }
        loadGeneration += 1
        let generation = loadGeneration
        activeTask = Task { [weak self] in
            // KaraokeAPIClient.data throws on non-2xx and posts
            // .karaokeSessionExpired on 401.
            let data = try? await KaraokeAPIClient.data(for: request)
            self?.applyArtistsResponse(data, reset: reset, generation: generation)
        }
    }

    private func applyArtistsResponse(
        _ data: Data?,
        reset: Bool,
        generation: Int
    ) {
        guard generation == loadGeneration else { return }
        defer {
            activeTask = nil
            isLoading = false
        }

        guard let data,
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
@Observable
final class ArtistDetailViewModel {
    var artist: Artist?
    var isLoading = false
    private(set) var hasLoadedDetail = false
    var errorMessage: String?
    private var loadedID: String?
    private var loadGeneration = 0
    @ObservationIgnored private var activeTask: Task<Void, Never>?

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
        activeTask = Task { [weak self] in
            do {
                let data = try await KaraokeAPIClient.data(for: request)
                self?.applyArtistDetailResponse(data, error: nil, id: id, generation: generation)
            } catch let error as URLError {
                self?.applyArtistDetailResponse(nil, error: error, id: id, generation: generation)
            } catch {
                // Non-2xx and other API failures map to the generic load error.
                self?.applyArtistDetailResponse(nil, error: nil, id: id, generation: generation)
            }
        }
    }

    private func applyArtistDetailResponse(
        _ data: Data?,
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
        guard let data
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
