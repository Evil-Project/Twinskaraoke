import Combine
import Foundation
import Observation

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
@Observable
final class PublicPlaylistsViewModel {
    var playlists: [Playlist] = []
    var isLoadingMore = false
    private var canLoadMore = true
    private var hasLoaded = false
    private var requestToken = 0
    private let pageSize = 25
    @ObservationIgnored private let refreshTracker = RefreshTracker()

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

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the playlists have actually finished loading.
    func refreshPublicPlaylists() async {
        refresh()
        await refreshTracker.wait()
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
        let task = Task { [weak self] in
            guard let self else { return }
            // defer, not a trailing statement: the token guards below return
            // from the whole closure, which would otherwise strand
            // isLoadingMore at true and permanently block pagination.
            //
            // Only the request that still owns the token clears the flag. A
            // superseded load-more clearing it would let pagination restart
            // from stale playlists while the replacing fetch is still in
            // flight. Whichever request is newest always matches, so the flag
            // still cannot be stranded.
            defer {
                if token == requestToken { isLoadingMore = false }
            }
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
                // Keep the current items on a failed replace fetch so the view
                // can retry instead of landing on a dead-end empty state.
                canLoadMore = false
            }
        }
        // Only the replacing fetch is what pull-to-refresh waits on; tracking a
        // load-more here would make a refresh return as soon as pagination did.
        // Safe to cancel what it supersedes: both the success and failure paths
        // below bail unless they still own `requestToken`.
        if replace { refreshTracker.track(task, cancellingPrevious: true) }
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
@Observable
final class TopChartViewModel {
    var songs: [Song] = []
    var weeklyTrending: [Song] = []
    private var hasLoaded = false
    private var requestToken = 0
    @ObservationIgnored private let refreshTracker = RefreshTracker()

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
        // Safe to cancel what it supersedes: the response is dropped unless it
        // still owns `requestToken`.
        refreshTracker.track(Task { [weak self] in
            guard let self else { return }
            async let allTime = try? KaraokeAPIClient.trendingSongs(days: "all")
            async let weekly = try? KaraokeAPIClient.trendingSongs(take: 20)
            let allTimeSongs = await allTime ?? []
            let weeklySongs = await weekly ?? []
            guard token == requestToken else { return }
            songs = allTimeSongs
            weeklyTrending = weeklySongs
        }, cancellingPrevious: true)
    }

    func refresh() {
        hasLoaded = false
        loadIfNeeded()
    }

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the charts have actually finished loading.
    func refreshTopChart() async {
        refresh()
        await refreshTracker.wait()
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
@Observable
final class GenresViewModel {
    var genres: [GenreSummary] = []
    var artworkURLs: [String: URL] = [:]
    var firstSongs: [String: Song] = [:]
    var allSongs: [String: [Song]] = [:]
    var isLoading = false
    var isLoadingMore = false
    var canLoadMore = true
    private(set) var failedDetailIDs = Set<String>()
    @ObservationIgnored private var page = 0
    @ObservationIgnored private let pageSize = 50
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var genreDetailOrder: [String] = []
    @ObservationIgnored private let maxCachedGenreDetails = 30
    @ObservationIgnored private var detailRequestsInFlight = Set<String>()
    @ObservationIgnored private var pendingDetailOrder: [String] = []
    @ObservationIgnored private var pendingDetails: [String: GenreSummary] = [:]
    @ObservationIgnored private var detailTasks: [String: Task<Void, Never>] = [:]
    // Observed so views can key work on it: a purge cancels in-flight detail
    // tasks, and without a generation-keyed restart those views would spin
    // forever on their loading branch.
    private(set) var detailGeneration: UInt64 = 0
    @ObservationIgnored private var pageGeneration: UInt64 = 0
    @ObservationIgnored private var detailFailureDates: [String: Date] = [:]
    @ObservationIgnored private let maxConcurrentDetailRequests = 4
    @ObservationIgnored private var genresNeedingFallback = Set<String>()
    @ObservationIgnored private var memoryWarningCancellable: AnyCancellable?
    @ObservationIgnored private var fallbackObservation: ObservationToken?
    @ObservationIgnored private let refreshTracker = RefreshTracker()

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
        fallbackObservation = observeContinuously({
            _ = FallbackArtRevision.shared.revision
        }, onChange: { [weak self] in
            self?.assignPendingFallbackArtwork()
        })
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
        // Bypass the isLoading guard so a pull-to-refresh during the initial
        // fetch starts a new replace-fetch; the new pageGeneration token in
        // fetchPage invalidates the in-flight response.
        isLoading = false
        loadIfNeeded()
    }

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the genre page has actually finished loading. Only the page fetch
    /// is awaited — per-genre detail requests stream in afterwards by design.
    func refreshGenres() async {
        refresh()
        await refreshTracker.wait()
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
            let request = try? KaraokeAPIClient.request(
                path: "/api/filters/genres",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "pageSize", value: String(pageSize)),
                ]
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
        let task = Task { [weak self] in
            let data = try? await KaraokeAPIClient.data(for: request)
            self?.applyGenrePageResponse(data, page: page, replace: replace, generation: generation)
        }
        // Only the replacing fetch is what pull-to-refresh waits on; tracking a
        // load-more here would make a refresh return as soon as pagination did.
        // Cancelling matters more here than elsewhere: `refresh()` deliberately
        // clears `isLoading` to get past the guard above, so a repeated refresh
        // really can start a second page fetch. The response is dropped unless
        // it still owns `pageGeneration`.
        if replace { refreshTracker.track(task, cancellingPrevious: true) }
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
        let task = Task { [weak self] in
            let data = try? await KaraokeAPIClient.data(for: request)
            self?.applyGenreDetailResponse(data, for: genre, generation: generation)
        }
        detailTasks[genre.id] = task
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
@Observable
final class SearchCategorySongsViewModel {
    var songs: [Song] = []
    var isLoading = false
    private var loadFailed = false
    private(set) var hasLoaded = false
    private let query: String
    private var requestToken = 0
    @ObservationIgnored private let refreshTracker = RefreshTracker()

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

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the category songs have actually finished loading.
    func refreshCategory() async {
        refresh()
        await refreshTracker.wait()
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

        // Safe to cancel what it supersedes: both `applyResponse` and
        // `applyFailure` bail unless they still own `requestToken`.
        refreshTracker.track(Task { [weak self] in
            guard let self else { return }
            do {
                let songs = try await KaraokeAPIClient.searchSongs(query: query, pageSize: 100)
                applyResponse(songs, token: token)
            } catch {
                applyFailure(token: token)
            }
        }, cancellingPrevious: true)
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
@Observable
final class SearchViewModel {
    var results: [Song] = []
    var searchText = "" {
        didSet { scheduleSearch() }
    }
    var isSearching = false
    var searchErrorMessage: String?

    /// Whether the field holds a query the search pipeline would actually run.
    /// Views must branch on this rather than `!searchText.isEmpty`: the
    /// pipeline trims before searching, so whitespace-only input clears the
    /// results, and a raw emptiness check would then show a "no results" state
    /// for a query that was never issued instead of the browse categories.
    ///
    /// Deliberately a derived value: `searchText` is two-way bound to the
    /// search field, so trimming it at publish time would swallow spaces as
    /// the user types them.
    var hasActiveQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ObservationIgnored private var queryToken: Int = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastDispatchedQuery = ""

    /// Replaces the former `$searchText.debounce().removeDuplicates()` pipeline:
    /// `@Observable` has no publisher projection, so the 500ms coalescing and
    /// the duplicate-query suppression are done here instead. Trimming still
    /// happens before the duplicate check, so edits that only change
    /// surrounding whitespace ("abc" -> "abc ") don't refire an identical
    /// search request.
    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query != lastDispatchedQuery else { return }
            lastDispatchedQuery = query
            if query.isEmpty { clearSearch() } else { search(query) }
        }
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
