import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    private enum TopPicksSource: Sendable {
        case publicPlaylists
        case setlists
    }

    @Published var trending: [Song] = []
    @Published var suggestions: [Song] = []
    @Published var recentPlaylists: [Playlist] = []
    @Published var newReleases: [Song] = []
    @Published var isLoading = false
    @Published var isLoadingMoreTopPicks = false
    @Published var canLoadMoreTopPicks = true
    @Published var loadErrorMessage: String?
    @Published private(set) var newLoadErrorMessage: String?
    @Published var latestSingle: Song?
    @Published var latestSingleContext: [Song] = []
    private var hasLoaded = false
    private var loadGeneration = 0
    private var homeLoadTask: Task<Void, Never>?
    private var topPicksLoadTask: Task<Void, Never>?
    private var topPicksPage = 0
    private let topPicksPageSize = 12
    private var topPicksSource: TopPicksSource = .setlists

    init() {
        fetchHomeData()
    }

    func fetchHomeData(force: Bool = false) {
        guard force || !hasLoaded else { return }
        startHomeDataLoad(force: force)
    }

    func refresh() async {
        let task = startHomeDataLoad(force: true)
        await task.value
    }

    @discardableResult
    private func startHomeDataLoad(force: Bool) -> Task<Void, Never> {
        if AppRuntime.isUITestMode {
            applyUITestFixture()
            return Task {}
        }

        loadGeneration += 1
        let generation = loadGeneration
        homeLoadTask?.cancel()
        if force {
            topPicksLoadTask?.cancel()
            topPicksLoadTask = nil
            isLoadingMoreTopPicks = false
        }

        hasLoaded = true
        loadErrorMessage = nil
        newLoadErrorMessage = nil
        isLoading = !hasVisibleContent

        let task = Task { [weak self] in
            guard let self else { return }
            await performHomeDataLoad(generation: generation)
        }
        homeLoadTask = task
        return task
    }

    private var hasVisibleContent: Bool {
        !trending.isEmpty
            || !suggestions.isEmpty
            || !recentPlaylists.isEmpty
            || !newReleases.isEmpty
            || latestSingle != nil
    }

    var hasNewVisibleContent: Bool {
        !trending.isEmpty
            || !recentPlaylists.isEmpty
            || !newReleases.isEmpty
    }

    private func performHomeDataLoad(generation: Int) async {
        async let trendingResponse = try? KaraokeAPIClient.trendingSongs(take: 20)
        async let suggestionsResponse = try? KaraokeAPIClient.songSuggestions(take: 20)
        async let topPicksResponse = fetchInitialTopPicks(startIndex: 0)
        async let newReleasesResponse = try? KaraokeAPIClient.latestReleases()

        let (loadedTrending, loadedSuggestions, loadedTopPicks, loadedNewReleases) = await (
            trendingResponse,
            suggestionsResponse,
            topPicksResponse,
            newReleasesResponse
        )

        guard generation == loadGeneration, !Task.isCancelled else { return }

        if let loadedTrending {
            trending = loadedTrending
        }
        if let loadedSuggestions {
            suggestions = loadedSuggestions
        }
        if let loadedTopPicks {
            topPicksSource = loadedTopPicks.source
            recentPlaylists = loadedTopPicks.playlists
            topPicksPage = 1
            canLoadMoreTopPicks = loadedTopPicks.playlists.count == topPicksPageSize
        }
        if let loadedNewReleases {
            newReleases = loadedNewReleases
            latestSingle = loadedNewReleases.first
            latestSingleContext = loadedNewReleases
        }

        isLoading = false
        loadErrorMessage = hasVisibleContent
            ? nil
            : "Home couldn't be loaded. Check your connection and try again."
        newLoadErrorMessage = hasNewVisibleContent
            ? nil
            : "New music couldn't be loaded. Check your connection and try again."
        homeLoadTask = nil
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
        let generation = loadGeneration
        topPicksLoadTask?.cancel()
        topPicksLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let playlists: [Playlist] = switch source {
                case .setlists:
                    try await KaraokeAPIClient.playlists(
                        startIndex: startIndex,
                        pageSize: pageSize,
                        isSetlist: true,
                        sortDescending: true
                    )
                case .publicPlaylists:
                    try await KaraokeAPIClient.publicPlaylists(
                        startIndex: startIndex,
                        pageSize: pageSize
                    )
                }
                guard generation == loadGeneration, !Task.isCancelled else { return }
                if !playlists.isEmpty {
                    let existing = Set(recentPlaylists.map(\.id))
                    recentPlaylists += playlists.filter { !existing.contains($0.id) }
                    topPicksPage += 1
                    canLoadMoreTopPicks = playlists.count == topPicksPageSize
                } else {
                    canLoadMoreTopPicks = false
                }
            } catch {
                guard generation == loadGeneration, !Task.isCancelled else { return }
            }
            isLoadingMoreTopPicks = false
            topPicksLoadTask = nil
        }
    }

    private func fetchInitialTopPicks(
        startIndex: Int
    ) async -> (source: TopPicksSource, playlists: [Playlist])? {
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

        guard !Task.isCancelled else { return nil }
        do {
            let fallback = try await KaraokeAPIClient.publicPlaylists(
                startIndex: startIndex,
                pageSize: pageSize
            )
            return (.publicPlaylists, fallback)
        } catch {
            return nil
        }
    }

    private func applyUITestFixture() {
        hasLoaded = true
        isLoading = false
        isLoadingMoreTopPicks = false
        canLoadMoreTopPicks = false
        loadErrorMessage = nil
        newLoadErrorMessage = nil
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
}
