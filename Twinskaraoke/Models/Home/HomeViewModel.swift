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
    // Bookkeeping the views never read; keep it out of the observation graph.
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var topPicksPage = 0
    @ObservationIgnored private let topPicksPageSize = 12
    @ObservationIgnored private var topPicksSource: TopPicksSource = .setlists
    @ObservationIgnored private var dataGeneration = 0
    @ObservationIgnored private var homeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var topPicksLoadMoreTask: Task<Void, Never>?

    // No work in init. This type is held in `@State`, whose initial-value
    // expression is re-evaluated on every re-initialization of the owning view
    // struct (only the first instance is kept). `@StateObject` took an
    // @autoclosure and evaluated it once, so an init-time fetch was safe there
    // and is a request flood here. The fetch is driven from the view's .task
    // instead, and `hasLoaded` keeps it to one round trip.

    func fetchHomeData(force: Bool = false) {
        if AppRuntime.isUITestMode {
            applyUITestFixture()
            return
        }

        if hasLoaded, !force { return }
        homeLoadTask?.cancel()
        topPicksLoadMoreTask?.cancel()
        topPicksLoadMoreTask = nil
        dataGeneration += 1
        let generation = dataGeneration
        hasLoaded = true
        // Only swap to the skeleton on the first load; a pull-to-refresh with
        // existing content keeps it on screen until the new data arrives.
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
            // Match the sections above: a failed refresh keeps the existing
            // New Releases shelf instead of erasing it mid-session.
            if let loadedReleases {
                newReleases = loadedReleases
                latestSingle = loadedReleases.first
                latestSingleContext = loadedReleases
            }
            isLoading = false
            homeLoadTask = nil
        }
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
            guard let self else { return }
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
            guard !Task.isCancelled, dataGeneration == generation else { return }
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

    private func applyUITestFixture() {
        hasLoaded = true
        isLoading = false
        isLoadingMoreTopPicks = false
        canLoadMoreTopPicks = false
        topPicksSource = .setlists

        let fixtureSongs = Self.fixtureSongs
        trending = Array(fixtureSongs.suffix(4))
        suggestions = Array(fixtureSongs.prefix(4))
        newReleases = fixtureSongs
        latestSingle = fixtureSongs.first
        latestSingleContext = fixtureSongs
        recentPlaylists = [
            UITestFixtures.playlist(
                id: "ui-home-playlist-essentials",
                name: "Karaoke Essentials",
                songs: Array(fixtureSongs.prefix(4))
            ),
            UITestFixtures.playlist(
                id: "ui-home-playlist-pop",
                name: "Pop Covers",
                songs: Array(fixtureSongs.dropFirst(2).prefix(4))
            ),
            UITestFixtures.playlist(
                id: "ui-home-playlist-night",
                name: "Late Night Singalong",
                songs: Array(fixtureSongs.suffix(4))
            ),
        ]
    }

    private static var fixtureSongs: [Song] {
        [
            UITestFixtures.song(
                id: "ui-home-song-1",
                title: "Wake Me Up Before You Go-Go",
                originalArtists: ["Wham!"],
                coverArtists: ["Neuro"]
            ),
            UITestFixtures.song(
                id: "ui-home-song-2",
                title: "Hero",
                originalArtists: ["Mili"],
                coverArtists: ["Neuro"]
            ),
            UITestFixtures.song(
                id: "ui-home-song-3",
                title: "Cure For Me",
                originalArtists: ["AURORA"],
                coverArtists: ["Neuro"]
            ),
            UITestFixtures.song(
                id: "ui-home-song-4",
                title: "Be My Star",
                originalArtists: ["LEVEL NINE"],
                coverArtists: ["Neuro"]
            ),
            UITestFixtures.song(
                id: "ui-home-song-5",
                title: "Young and Beautiful",
                originalArtists: ["Lana Del Rey"],
                coverArtists: ["Neuro"]
            ),
            UITestFixtures.song(
                id: "ui-home-song-6",
                title: "Send Me an Angel",
                originalArtists: ["Scorpions"],
                coverArtists: ["Neuro"]
            ),
        ]
    }

    deinit {
        homeLoadTask?.cancel()
        topPicksLoadMoreTask?.cancel()
    }
}
