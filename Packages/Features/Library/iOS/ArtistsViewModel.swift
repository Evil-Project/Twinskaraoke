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

    /// Server matches for `searchedQuery`. `artists` holds only the pages
    /// scrolled into view, so filtering it alone searched the first few dozen
    /// names: anyone further down the alphabet came back as No Results.
    private(set) var searchResults: [Artist] = []
    private(set) var searchedQuery = ""
    private(set) var isSearching = false
    @ObservationIgnored private let searchArtists: @MainActor (String) async throws -> [Artist]

    init(searchArtists: @escaping @MainActor (String) async throws -> [Artist] = ArtistsViewModel.remoteSearch) {
        self.searchArtists = searchArtists
    }

    /// Everything that matches `query`: loaded artists straight away, plus the
    /// server's matches once they arrive, in name order.
    func matches(for query: String) -> [Artist] {
        let local = artists.filter { Self.artist($0, matches: query) }
        guard searchedQuery == query else { return local }
        var seen = Set(local.map(\.id))
        let merged = local + searchResults.filter { seen.insert($0.id).inserted }
        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Runs from the view's `task(id:)`, which cancels it when the query
    /// changes; that is also the debounce.
    func search(_ query: String) async {
        guard !query.isEmpty else {
            searchedQuery = ""
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(300))
            let found = try await searchArtists(query)
            try Task.checkCancellation()
            // The endpoint matches loosely; keep what the list's own filter
            // would have kept.
            searchResults = found.filter { Self.artist($0, matches: query) }
            searchedQuery = query
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchedQuery = query
            isSearching = false
        }
    }

    private static func artist(_ artist: Artist, matches query: String) -> Bool {
        artist.name.localizedCaseInsensitiveContains(query)
            || artist.summary?.localizedCaseInsensitiveContains(query) == true
    }

    static func remoteSearch(_ query: String) async throws -> [Artist] {
        let request = try KaraokeAPIClient.request(
            path: "/api/artists",
            queryItems: [
                URLQueryItem(name: "startIndex", value: "0"),
                URLQueryItem(name: "pageSize", value: "50"),
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "sortBy", value: "Name"),
                URLQueryItem(name: "sortDescending", value: "False"),
            ]
        )
        let data = try await KaraokeAPIClient.data(for: request)
        return try JSONDecoder().decode(LossyArray<Artist>.self, from: data).elements
    }

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
            errorMessage = String(localized: "The artist could not be loaded right now.")
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
            errorMessage = String(localized: "Check your connection and try again.")
            return
        }
        guard let data
        else {
            errorMessage = String(localized: "The artist could not be loaded right now.")
            return
        }

        guard let decoded = try? JSONDecoder().decode(Artist.self, from: data) else {
            errorMessage = String(localized: "The artist could not be loaded right now.")
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
