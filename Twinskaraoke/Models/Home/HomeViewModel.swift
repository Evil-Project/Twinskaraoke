import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private enum TopPicksSource {
        case publicPlaylists
        case setlists
    }

    var trending: [Song] = []
    var suggestions: [Song] = []
    var recentPlaylists: [Playlist] = []
    var newReleases: [Song] = []
    var isLoading = false
    var isLoadingMoreTopPicks = false
    var canLoadMoreTopPicks = true
    var latestSingle: Song?
    var latestSingleContext: [Song] = []
    /// Set once a load has finished, whether or not anything came back.
    private(set) var hasFinishedLoading = false

    /// Home has nothing from the network to show: every request failed (as
    /// when the app opens offline) or came back empty. Home used to render as
    /// a bare title with no way to tell why, and stayed that way until pulled
    /// to refresh.
    var homeIsEmpty: Bool {
        newIsEmpty && suggestions.isEmpty
    }

    /// The same for New, which does not show suggestions: suggestions alone
    /// would otherwise leave New blank while Home still had something.
    var newIsEmpty: Bool {
        hasFinishedLoading && !isLoading
            && trending.isEmpty && recentPlaylists.isEmpty && newReleases.isEmpty
    }
    // Bookkeeping the views never read; keep it out of the observation graph.
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var topPicksPage = 0
    @ObservationIgnored private let topPicksPageSize = 12
    @ObservationIgnored private var topPicksSource: TopPicksSource = .setlists
    @ObservationIgnored private var dataGeneration = 0
    @ObservationIgnored private var homeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var topPicksLoadMoreTask: Task<Void, Never>?

    func fetchHomeData(force: Bool = false) {
        if hasLoaded, !force { return }
        homeLoadTask?.cancel()
        topPicksLoadMoreTask?.cancel()
        topPicksLoadMoreTask = nil
        dataGeneration += 1
        let generation = dataGeneration
        hasLoaded = true
        if trending.isEmpty, suggestions.isEmpty, recentPlaylists.isEmpty, newReleases.isEmpty {
            isLoading = true
        }
        isLoadingMoreTopPicks = false
        topPicksPage = 0
        canLoadMoreTopPicks = true
        homeLoadTask = Task { [weak self] in
            guard let self else { return }
            async let trendingResult = try? KaraokeAPIClient.trendingSongs(take: 20)
            async let suggestionsResult = try? KaraokeAPIClient.songSuggestions(take: 20)
            async let topPicksResult = fetchTopPicks(startIndex: 0)
            async let releasesResult = try? KaraokeAPIClient.latestReleases()

            let (loadedTrending, loadedSuggestions, loadedTopPicks, loadedReleases) = await (
                trendingResult,
                suggestionsResult,
                topPicksResult,
                releasesResult
            )
            guard !Task.isCancelled, dataGeneration == generation else { return }

            if let loadedTrending { trending = loadedTrending }
            if let loadedSuggestions { suggestions = loadedSuggestions }
            if let playlists = loadedTopPicks.playlists {
                topPicksSource = loadedTopPicks.source
                recentPlaylists = playlists
                topPicksPage = 1
                canLoadMoreTopPicks = playlists.count == topPicksPageSize
            }
            if let loadedReleases {
                newReleases = loadedReleases
                latestSingle = loadedReleases.first
                latestSingleContext = loadedReleases
            }
            hasFinishedLoading = true
            isLoading = false
            homeLoadTask = nil
            // Let the next appearance or activation try again instead of
            // treating a load that left a screen empty as done.
            if newIsEmpty { hasLoaded = false }
        }
    }

    /// Retries a load that left Home or New with nothing to show. Called when
    /// the app becomes active, which is usually when a connection has come
    /// back.
    func retryIfLoadFailed() {
        guard newIsEmpty, homeLoadTask == nil else { return }
        fetchHomeData(force: true)
    }

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the home data has actually finished loading.
    func refreshHomeData() async {
        fetchHomeData(force: true)
        await homeLoadTask?.value
    }

    func loadMoreTopPicksIfNeeded(current: Playlist) {
        guard let idx = recentPlaylists.firstIndex(where: { $0.id == current.id }) else { return }
        if idx >= recentPlaylists.count - 3, !isLoadingMoreTopPicks, canLoadMoreTopPicks {
            loadMoreTopPicks()
        }
    }

    func topPicksURLForList(startIndex: Int, pageSize: Int) -> String {
        switch topPicksSource {
        case .setlists:
            "\(StorageHost.api)/api/playlists?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=&sortDescending=True&isSetlist=True&year=0"
        case .publicPlaylists:
            "\(StorageHost.api)/api/playlist/public?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=UpdatedAt&sortDescending=True"
        }
    }

    private func loadMoreTopPicks() {
        isLoadingMoreTopPicks = true
        let startIndex = topPicksPage * topPicksPageSize
        let source = topPicksSource
        let pageSize = topPicksPageSize
        let generation = dataGeneration
        topPicksLoadMoreTask = Task { [weak self] in
            let playlists: [Playlist] = switch source {
            case .setlists:
                await (try? KaraokeAPIClient.playlists(
                    startIndex: startIndex,
                    pageSize: pageSize,
                    isSetlist: true,
                    sortDescending: true
                )) ?? []
            case .publicPlaylists:
                await (try? KaraokeAPIClient.publicPlaylists(
                    startIndex: startIndex,
                    pageSize: pageSize
                )) ?? []
            }
            guard !Task.isCancelled, let self, self.dataGeneration == generation else { return }
            if !playlists.isEmpty {
                let existing = Set(recentPlaylists.map(\.id))
                recentPlaylists += playlists.filter { !existing.contains($0.id) }
                topPicksPage += 1
                canLoadMoreTopPicks = playlists.count == topPicksPageSize
            } else {
                canLoadMoreTopPicks = false
            }
            isLoadingMoreTopPicks = false
            topPicksLoadMoreTask = nil
        }
    }

    private func fetchTopPicks(
        startIndex: Int
    ) async -> (source: TopPicksSource, playlists: [Playlist]?) {
        let pageSize = topPicksPageSize
        let setlists = await (try? KaraokeAPIClient.playlists(
            startIndex: startIndex,
            pageSize: pageSize,
            isSetlist: true,
            sortDescending: true
        )) ?? []
        if !setlists.isEmpty {
            return (.setlists, setlists)
        }

        let fallback = try? await KaraokeAPIClient.publicPlaylists(
            startIndex: startIndex,
            pageSize: pageSize
        )
        return (.publicPlaylists, fallback)
    }

    deinit {
        homeLoadTask?.cancel()
        topPicksLoadMoreTask?.cancel()
    }
}
