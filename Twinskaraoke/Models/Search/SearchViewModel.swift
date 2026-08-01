import Combine
import Foundation

#if canImport(UIKit)
    import UIKit
#endif

nonisolated struct GenreSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let songCount: Int

    enum CodingKeys: String, CodingKey { case id, name, songCount, count }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if let v = try c.decodeIfPresent(Int.self, forKey: .songCount) {
            songCount = v
        } else {
            songCount = (try? c.decode(Int.self, forKey: .count)) ?? 0
        }
    }
}

struct GenreDetail: Decodable {
    let id: String
    let name: String
    let songs: [Song]?
}

@MainActor
final class PublicPlaylistsViewModel: ObservableObject {
    typealias PageLoader = @Sendable (_ startIndex: Int, _ pageSize: Int) async throws -> [Playlist]

    @Published var playlists: [Playlist] = []
    @Published private(set) var isLoading = false
    @Published var isLoadingMore = false
    @Published private(set) var loadFailed = false
    private var canLoadMore = true
    private var hasLoaded = false
    private let pageSize = 25
    private let pageLoader: PageLoader

    init(
        pageLoader: @escaping PageLoader = { startIndex, pageSize in
            try await KaraokeAPIClient.publicPlaylists(
                startIndex: startIndex,
                pageSize: pageSize
            )
        }
    ) {
        self.pageLoader = pageLoader
    }

    @discardableResult
    func loadIfNeeded() -> Task<Void, Never>? {
        guard !hasLoaded, !isLoading else { return nil }
        if AppRuntime.isUITestMode {
            hasLoaded = true
            applyUITestFixture()
            return nil
        }
        return fetchPage(startIndex: 0, replace: true)
    }

    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard !isLoading else { return nil }
        hasLoaded = false
        return loadIfNeeded()
    }

    func loadMoreIfNeeded(current: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == current.id }) else { return }
        if idx >= playlists.count - 4, !isLoadingMore, canLoadMore {
            fetchPage(startIndex: playlists.count, replace: false)
        }
    }

    func urlForList(startIndex: Int, pageSize: Int) -> String {
        "\(StorageHost.api)/api/playlist/public?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=UpdatedAt&sortDescending=True"
    }

    @discardableResult
    private func fetchPage(startIndex: Int, replace: Bool) -> Task<Void, Never> {
        if replace {
            isLoading = true
            loadFailed = false
        } else {
            isLoadingMore = true
        }
        let pageLoader = pageLoader
        let pageSize = pageSize
        return Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await pageLoader(startIndex, pageSize)
                if replace {
                    playlists = items
                    hasLoaded = true
                    loadFailed = false
                } else {
                    let existing = Set(playlists.map(\.id))
                    playlists += items.filter { !existing.contains($0.id) }
                }
                canLoadMore = items.count >= pageSize
            } catch {
                if replace {
                    hasLoaded = false
                    loadFailed = playlists.isEmpty
                }
            }
            isLoading = false
            isLoadingMore = false
        }
    }

    private func applyUITestFixture() {
        playlists = Self.uiTestFixturePlaylists
        isLoading = false
        isLoadingMore = false
        loadFailed = false
        canLoadMore = false
    }

    private static var uiTestFixturePlaylists: [Playlist] {
        let songs = uiTestFixtureSongs
        return [
            Playlist(
                id: "ui-search-playlist-essentials",
                name: "Karaoke Essentials",
                songCount: songs.count,
                media: nil,
                mosaicMedia: nil,
                songListDTOs: songs
            ),
            Playlist(
                id: "ui-search-playlist-dance",
                name: "Dance Covers",
                songCount: 2,
                media: nil,
                mosaicMedia: nil,
                songListDTOs: Array(songs.suffix(2))
            ),
        ]
    }

    private static var uiTestFixtureSongs: [Song] {
        [
            UITestFixtures.song(
                id: "ui-search-song-1",
                title: "Wake Me Up Before You Go-Go",
                artist: "Wham!"
            ),
            UITestFixtures.song(id: "ui-search-song-2", title: "Hero", artist: "Mili"),
            UITestFixtures.song(id: "ui-search-song-3", title: "Cure For Me", artist: "AURORA"),
        ]
    }
}

@MainActor
final class TopChartViewModel: ObservableObject {
    typealias SongsLoader = @Sendable () async throws -> [Song]

    @Published var songs: [Song] = []
    @Published var weeklyTrending: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    private var hasLoaded = false
    private let allTimeLoader: SongsLoader
    private let weeklyLoader: SongsLoader

    init(
        allTimeLoader: @escaping SongsLoader = {
            try await KaraokeAPIClient.trendingSongs(days: "all")
        },
        weeklyLoader: @escaping SongsLoader = {
            try await KaraokeAPIClient.trendingSongs(take: 20)
        }
    ) {
        self.allTimeLoader = allTimeLoader
        self.weeklyLoader = weeklyLoader
    }

    @discardableResult
    func loadIfNeeded() -> Task<Void, Never>? {
        guard !hasLoaded, !isLoading else { return nil }
        if AppRuntime.isUITestMode {
            hasLoaded = true
            applyUITestFixture()
            return nil
        }
        isLoading = true
        loadFailed = false
        let allTimeLoader = allTimeLoader
        let weeklyLoader = weeklyLoader
        return Task { [weak self] in
            async let allTime = try? allTimeLoader()
            async let weekly = try? weeklyLoader()
            let loadedSongs = await allTime
            let loadedWeeklyTrending = await weekly
            guard let self else { return }

            if let loadedSongs {
                songs = loadedSongs
            }
            if let loadedWeeklyTrending {
                weeklyTrending = loadedWeeklyTrending
            }
            hasLoaded = loadedSongs != nil && loadedWeeklyTrending != nil
            loadFailed = loadedSongs == nil && songs.isEmpty
            isLoading = false
        }
    }

    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard !isLoading else { return nil }
        hasLoaded = false
        return loadIfNeeded()
    }

    private func applyUITestFixture() {
        songs = Self.uiTestFixtureSongs
        weeklyTrending = Array(Self.uiTestFixtureSongs.prefix(2))
        isLoading = false
        loadFailed = false
    }

    private static var uiTestFixtureSongs: [Song] {
        [
            UITestFixtures.song(
                id: "ui-top-song-1",
                title: "Wake Me Up Before You Go-Go",
                artist: "Wham!"
            ),
            UITestFixtures.song(id: "ui-top-song-2", title: "Hero", artist: "Mili"),
            UITestFixtures.song(id: "ui-top-song-3", title: "Cure For Me", artist: "AURORA"),
        ]
    }
}

@MainActor
final class GenresViewModel: ObservableObject {
    @Published var genres: [GenreSummary] = []
    @Published var artworkURLs: [String: URL] = [:]
    @Published var firstSongs: [String: Song] = [:]
    @Published var allSongs: [String: [Song]] = [:]
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var canLoadMore = true
    private var page = 0
    private let pageSize = 50
    private var hasLoaded = false
    private var genreDetailOrder: [String] = []
    private let maxCachedGenreDetails = 30
    private var detailRequestsInFlight = Set<String>()
    private var genresNeedingFallback = Set<String>()
    private var fallbackCancellable: AnyCancellable?

    init() {
        #if canImport(UIKit)
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.clearCachedGenreDetails()
                }
            }
        #endif
        fallbackCancellable = FallbackArtProvider.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor [weak self] in self?.assignPendingFallbackArtwork() }
            }
    }

    private func assignPendingFallbackArtwork() {
        for id in genresNeedingFallback where artworkURLs[id] == nil {
            artworkURLs[id] = FallbackArtProvider.shared.randomURL
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        fetchPage(0, replace: true)
    }

    func loadMoreIfNeeded(current: GenreSummary) {
        guard let idx = genres.firstIndex(where: { $0.id == current.id }) else { return }
        if idx >= genres.count - 6, !isLoadingMore, canLoadMore {
            fetchPage(page, replace: false)
        }
    }

    private func clearCachedGenreDetails() {
        allSongs.removeAll()
        firstSongs.removeAll()
        genreDetailOrder.removeAll()
    }

    private func fetchPage(_ page: Int, replace: Bool) {
        guard replace || (!isLoadingMore && canLoadMore) else { return }
        guard !isLoading else { return }
        guard
            let url = URL(
                string:
                "\(StorageHost.api)/api/filters/genres?page=\(page)&pageSize=\(pageSize)"
            )
        else { return }
        if replace {
            isLoading = true
            detailRequestsInFlight.removeAll()
        } else {
            isLoadingMore = true
        }
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            Task { @MainActor [weak self, data, page, replace] in
                self?.applyGenrePageResponse(data, page: page, replace: replace)
            }
        }.resume()
    }

    private func applyGenrePageResponse(_ data: Data?, page: Int, replace: Bool) {
        defer {
            isLoading = false
            isLoadingMore = false
        }

        guard let data, let list = try? JSONDecoder().decode([GenreSummary].self, from: data) else {
            canLoadMore = false
            return
        }

        let filtered = list.filter { $0.songCount > 0 }
        if replace {
            genres = filtered
            hasLoaded = true
        } else {
            let existing = Set(genres.map(\.id))
            genres += filtered.filter { !existing.contains($0.id) }
        }
        canLoadMore = list.count == pageSize
        self.page = page + 1
        for genre in filtered {
            fetchDetail(for: genre)
        }
    }

    private func fetchDetail(for genre: GenreSummary) {
        if allSongs[genre.id] != nil { return }
        guard detailRequestsInFlight.insert(genre.id).inserted else { return }
        guard let url = URL(string: "\(StorageHost.api)/api/genres/\(genre.id)") else {
            detailRequestsInFlight.remove(genre.id)
            return
        }
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            Task { @MainActor [weak self, data, genre] in
                self?.applyGenreDetailResponse(data, for: genre)
            }
        }.resume()
    }

    private func applyGenreDetailResponse(_ data: Data?, for genre: GenreSummary) {
        defer { detailRequestsInFlight.remove(genre.id) }
        guard let data,
              let detail = try? JSONDecoder().decode(GenreDetail.self, from: data),
              let songs = detail.songs
        else {
            return
        }

        allSongs[genre.id] = songs
        if let first = songs.first {
            firstSongs[genre.id] = first
        }
        if let ownArtURL = songs.first(where: { $0.hasOwnArtwork })?.imageURL {
            genresNeedingFallback.remove(genre.id)
            artworkURLs[genre.id] = ownArtURL
        } else {
            genresNeedingFallback.insert(genre.id)
            artworkURLs[genre.id] = FallbackArtProvider.shared.randomURL
        }
        genreDetailOrder.removeAll { $0 == genre.id }
        genreDetailOrder.append(genre.id)
        while genreDetailOrder.count > maxCachedGenreDetails {
            let oldest = genreDetailOrder.removeFirst()
            allSongs.removeValue(forKey: oldest)
            firstSongs.removeValue(forKey: oldest)
        }
    }
}

@MainActor
final class SearchCategorySongsViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading = false
    @Published private var loadFailed = false
    @Published private(set) var hasLoaded = false
    private let query: String
    private var requestToken = 0

    init(query: String) {
        self.query = query
    }

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        hasLoaded = true
        fetch()
    }

    func refresh() {
        hasLoaded = true
        fetch()
    }

    var emptyStateMessage: String {
        if loadFailed {
            return "The category couldn’t be loaded. Check your connection and try again."
        }
        return "Try another category or search term."
    }

    private func fetch() {
        requestToken += 1
        let token = requestToken
        isLoading = true
        loadFailed = false

        Task { [weak self] in
            guard let self else { return }
            do {
                let songs = try await KaraokeAPIClient.searchSongs(query: query, pageSize: 100)
                applyResponse(songs, token: token)
            } catch {
                applyFailure(token: token)
            }
        }
    }

    private func applyResponse(_ loadedSongs: [Song], token: Int) {
        guard token == requestToken else { return }
        songs = loadedSongs
        loadFailed = false
        isLoading = false
    }

    private func applyFailure(token: Int) {
        guard token == requestToken else { return }
        loadFailed = songs.isEmpty
        isLoading = false
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    typealias SearchLoader = @Sendable (_ query: String, _ pageSize: Int) async throws -> [Song]

    @Published var results: [Song] = []
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var searchErrorMessage: String?
    private var cancellables = Set<AnyCancellable>()
    private var queryToken: Int = 0
    private var searchTask: Task<Void, Never>?
    private let searchLoader: SearchLoader

    init(
        debounceInterval: RunLoop.SchedulerTimeType.Stride = .milliseconds(500),
        searchLoader: @escaping SearchLoader = { query, pageSize in
            try await KaraokeAPIClient.searchSongs(query: query, pageSize: pageSize)
        }
    ) {
        self.searchLoader = searchLoader
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] query in
                self?.invalidateSearchForQueryEdit(query)
            })
            .debounce(for: debounceInterval, scheduler: RunLoop.main)
            .sink { [weak self] query in
                if !query.isEmpty { self?.search(query) } else { self?.clearSearch() }
            }
            .store(in: &cancellables)
    }

    deinit {
        searchTask?.cancel()
    }

    func retrySearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        search(query)
    }

    @discardableResult
    func search(_ query: String) -> Task<Void, Never>? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearch()
            return nil
        }
        queryToken += 1
        let token = queryToken
        results = []
        isSearching = true
        searchErrorMessage = nil
        searchTask?.cancel()
        let searchLoader = searchLoader

        let task = Task { [weak self] in
            do {
                let songs = try await searchLoader(trimmedQuery, 30)
                guard !Task.isCancelled, let self else { return }
                applySearchResponse(songs, token: token)
            } catch KaraokeAPIClient.APIError.httpStatus(_) {
                guard !Task.isCancelled, let self else { return }
                applySearchFailure("Search returned an unexpected response. Try again.", token: token)
            } catch KaraokeAPIClient.APIError.decodeFailed {
                guard !Task.isCancelled, let self else { return }
                applySearchFailure("Search results couldn't be read. Try again.", token: token)
            } catch {
                guard !Task.isCancelled, let self else { return }
                applySearchFailure("Check your connection and try again.", token: token)
            }
        }
        searchTask = task
        return task
    }

    private func invalidateSearchForQueryEdit(_ query: String) {
        queryToken += 1
        searchTask?.cancel()
        searchTask = nil
        results = []
        isSearching = !query.isEmpty
        searchErrorMessage = nil
    }

    private func clearSearch() {
        queryToken += 1
        searchTask?.cancel()
        searchTask = nil
        results = []
        isSearching = false
        searchErrorMessage = nil
    }

    private func applySearchResponse(_ loadedSongs: [Song], token: Int) {
        guard queryToken == token else { return }
        results = loadedSongs
        searchErrorMessage = nil
        isSearching = false
        searchTask = nil
    }

    private func applySearchFailure(_ message: String, token: Int) {
        guard queryToken == token else { return }
        results = []
        searchErrorMessage = message
        isSearching = false
        searchTask = nil
    }
}
