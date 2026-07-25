import Combine
import Foundation

#if canImport(UIKit)
    import UIKit
#endif

nonisolated struct GenreSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let songCount: Int

    init(id: String, name: String, songCount: Int) {
        self.id = id
        self.name = name
        self.songCount = songCount
    }

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
    @Published var playlists: [Playlist] = []
    @Published var isLoadingMore = false
    private var canLoadMore = true
    private var hasLoaded = false
    private var requestToken = 0
    private let pageSize = 25

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        if AppRuntime.isUITestMode {
            hasLoaded = true
            applyUITestFixture()
            return
        }
        hasLoaded = true
        fetchPage(startIndex: 0, replace: true)
    }

    func refresh() {
        hasLoaded = false
        canLoadMore = true
        loadIfNeeded()
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

    private func fetchPage(startIndex: Int, replace: Bool) {
        if replace {
            requestToken += 1
        } else {
            isLoadingMore = true
        }
        let token = requestToken
        Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await KaraokeAPIClient.publicPlaylists(
                    startIndex: startIndex,
                    pageSize: pageSize
                )
                guard token == requestToken else { return }
                if replace {
                    playlists = items
                } else {
                    let existing = Set(playlists.map(\.id))
                    playlists += items.filter { !existing.contains($0.id) }
                }
                canLoadMore = items.count >= pageSize
            } catch {
                guard token == requestToken else { return }
                if replace { playlists = [] }
                canLoadMore = false
            }
            isLoadingMore = false
        }
    }

    private func applyUITestFixture() {
        playlists = Self.uiTestFixturePlaylists
        isLoadingMore = false
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
    @Published var songs: [Song] = []
    @Published var weeklyTrending: [Song] = []
    private var hasLoaded = false
    private var requestToken = 0

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        if AppRuntime.isUITestMode {
            hasLoaded = true
            applyUITestFixture()
            return
        }
        hasLoaded = true
        requestToken += 1
        let token = requestToken
        Task { [weak self] in
            guard let self else { return }
            async let allTime = try? KaraokeAPIClient.trendingSongs(days: "all")
            async let weekly = try? KaraokeAPIClient.trendingSongs(take: 20)
            let allTimeSongs = await allTime ?? []
            let weeklySongs = await weekly ?? []
            guard token == requestToken else { return }
            songs = allTimeSongs
            weeklyTrending = weeklySongs
        }
    }

    func refresh() {
        hasLoaded = false
        loadIfNeeded()
    }

    private func applyUITestFixture() {
        songs = Self.uiTestFixtureSongs
        weeklyTrending = Array(Self.uiTestFixtureSongs.prefix(2))
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
    @Published private(set) var failedDetailIDs = Set<String>()
    private var page = 0
    private let pageSize = 50
    private var hasLoaded = false
    private var genreDetailOrder: [String] = []
    private let maxCachedGenreDetails = 30
    private var detailRequestsInFlight = Set<String>()
    private var pendingDetailOrder: [String] = []
    private var pendingDetails: [String: GenreSummary] = [:]
    private var detailTasks: [String: URLSessionDataTask] = [:]
    private var detailGeneration: UInt64 = 0
    private var pageGeneration: UInt64 = 0
    private var detailFailureDates: [String: Date] = [:]
    private let maxConcurrentDetailRequests = 4
    private var genresNeedingFallback = Set<String>()
    private var fallbackCancellable: AnyCancellable?
    private var memoryWarningCancellable: AnyCancellable?

    init() {
        #if canImport(UIKit)
            memoryWarningCancellable = NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.clearCachedGenreDetails() }
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
        if AppRuntime.isUITestMode {
            applyUITestFixture()
            return
        }
        fetchPage(0, replace: true)
    }

    func refresh() {
        hasLoaded = false
        loadIfNeeded()
    }

    func loadMoreIfNeeded(current: GenreSummary) {
        guard let idx = genres.firstIndex(where: { $0.id == current.id }) else { return }
        if idx >= genres.count - 6, !isLoadingMore, canLoadMore {
            fetchPage(page, replace: false)
        }
    }

    private func clearCachedGenreDetails() {
        detailGeneration &+= 1
        detailTasks.values.forEach { $0.cancel() }
        detailTasks.removeAll()
        detailRequestsInFlight.removeAll()
        pendingDetailOrder.removeAll()
        pendingDetails.removeAll()
        allSongs.removeAll()
        firstSongs.removeAll()
        genreDetailOrder.removeAll()
    }

    private func applyUITestFixture() {
        let fixtureGenres = [
            GenreSummary(id: "ui-genre-dance", name: "Dance", songCount: 3),
            GenreSummary(id: "ui-genre-pop", name: "Pop", songCount: 3),
            GenreSummary(id: "ui-genre-rock", name: "Rock", songCount: 3),
        ]
        let fixtureSongs = [
            UITestFixtures.song(id: "ui-genre-song-1", title: "Wake Me Up Before You Go-Go", artist: "Wham!"),
            UITestFixtures.song(id: "ui-genre-song-2", title: "Hero", artist: "Mili"),
            UITestFixtures.song(id: "ui-genre-song-3", title: "Cure For Me", artist: "AURORA"),
        ]

        genres = fixtureGenres
        allSongs = Dictionary(uniqueKeysWithValues: fixtureGenres.map { ($0.id, fixtureSongs) })
        firstSongs = Dictionary(uniqueKeysWithValues: fixtureGenres.map { ($0.id, fixtureSongs[0]) })
        hasLoaded = true
        canLoadMore = false
        isLoading = false
        isLoadingMore = false
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
            pageGeneration &+= 1
            isLoading = true
            pendingDetailOrder.removeAll()
            pendingDetails.removeAll()
        } else {
            isLoadingMore = true
        }
        let generation = pageGeneration
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            Task { @MainActor [weak self, data, page, replace, generation] in
                self?.applyGenrePageResponse(data, page: page, replace: replace, generation: generation)
            }
        }.resume()
    }

    private func applyGenrePageResponse(_ data: Data?, page: Int, replace: Bool, generation: UInt64) {
        guard generation == pageGeneration else { return }
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
    }

    func loadPreviewIfNeeded(for genre: GenreSummary) {
        guard artworkURLs[genre.id] == nil else { return }
        enqueueDetail(for: genre, priority: false)
    }

    func loadDetailIfNeeded(for genre: GenreSummary) {
        guard allSongs[genre.id] == nil else { return }
        failedDetailIDs.remove(genre.id)
        enqueueDetail(for: genre, priority: true)
    }

    private func enqueueDetail(for genre: GenreSummary, priority: Bool) {
        guard allSongs[genre.id] == nil, !detailRequestsInFlight.contains(genre.id) else { return }
        if !priority,
           let failedAt = detailFailureDates[genre.id],
           Date().timeIntervalSince(failedAt) < 30
        {
            return
        }
        if pendingDetails[genre.id] != nil {
            if priority {
                pendingDetailOrder.removeAll { $0 == genre.id }
                pendingDetailOrder.insert(genre.id, at: 0)
            }
            return
        }
        pendingDetails[genre.id] = genre
        if priority {
            pendingDetailOrder.insert(genre.id, at: 0)
        } else {
            pendingDetailOrder.append(genre.id)
        }
        startQueuedDetailRequests()
    }

    private func startQueuedDetailRequests() {
        while detailRequestsInFlight.count < maxConcurrentDetailRequests,
              let genreID = pendingDetailOrder.first
        {
            pendingDetailOrder.removeFirst()
            guard let genre = pendingDetails.removeValue(forKey: genreID),
                  detailRequestsInFlight.insert(genreID).inserted
            else { continue }
            fetchDetail(for: genre)
        }
    }

    private func fetchDetail(for genre: GenreSummary) {
        let generation = detailGeneration
        guard let request = try? KaraokeAPIClient.request(
            pathSegments: ["api", "genres", genre.id]
        ) else {
            detailRequestsInFlight.remove(genre.id)
            startQueuedDetailRequests()
            return
        }
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            Task { @MainActor [weak self, data, genre, generation] in
                self?.applyGenreDetailResponse(data, for: genre, generation: generation)
            }
        }
        detailTasks[genre.id] = task
        task.resume()
    }

    private func applyGenreDetailResponse(
        _ data: Data?,
        for genre: GenreSummary,
        generation: UInt64
    ) {
        guard generation == detailGeneration else { return }
        defer {
            detailTasks.removeValue(forKey: genre.id)
            detailRequestsInFlight.remove(genre.id)
            startQueuedDetailRequests()
        }
        guard let data,
              let detail = try? JSONDecoder().decode(GenreDetail.self, from: data),
              let songs = detail.songs
        else {
            detailFailureDates[genre.id] = Date()
            failedDetailIDs.insert(genre.id)
            return
        }

        detailFailureDates.removeValue(forKey: genre.id)
        failedDetailIDs.remove(genre.id)
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
    @Published var results: [Song] = []
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var searchErrorMessage: String?
    private var cancellables = Set<AnyCancellable>()
    private var queryToken: Int = 0
    private var searchTask: Task<Void, Never>?

    init() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                if !query.isEmpty { self?.search(query) } else { self?.clearSearch() }
            }
            .store(in: &cancellables)
    }

    func retrySearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        search(query)
    }

    func search(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearch()
            return
        }
        searchTask?.cancel()
        queryToken += 1
        let token = queryToken
        results = []
        isSearching = true
        searchErrorMessage = nil

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let songs = try await KaraokeAPIClient.searchSongs(query: trimmedQuery, pageSize: 30)
                guard !Task.isCancelled else { return }
                applySearchResponse(songs, token: token)
            } catch is CancellationError {
                return
            } catch KaraokeAPIClient.APIError.httpStatus(_) {
                guard !Task.isCancelled else { return }
                applySearchFailure("Search returned an unexpected response. Try again.", token: token)
            } catch KaraokeAPIClient.APIError.decodeFailed {
                guard !Task.isCancelled else { return }
                applySearchFailure("Search results couldn't be read. Try again.", token: token)
            } catch {
                guard !Task.isCancelled else { return }
                applySearchFailure("Check your connection and try again.", token: token)
            }
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        queryToken += 1
        results = []
        isSearching = false
        searchErrorMessage = nil
    }

    private func applySearchResponse(_ loadedSongs: [Song], token: Int) {
        guard queryToken == token else { return }
        searchTask = nil
        results = loadedSongs
        searchErrorMessage = nil
        isSearching = false
    }

    private func applySearchFailure(_ message: String, token: Int) {
        guard queryToken == token else { return }
        searchTask = nil
        results = []
        searchErrorMessage = message
        isSearching = false
    }

    deinit {
        searchTask?.cancel()
    }
}
