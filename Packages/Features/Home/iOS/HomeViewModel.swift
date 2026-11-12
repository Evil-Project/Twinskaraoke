import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class HomeViewModel {
    /// The requests behind Home and New, replaced in tests.
    struct Requests {
        var trending: @MainActor () async throws -> [Song]
        var suggestions: @MainActor () async throws -> [Song]
        var releases: @MainActor () async throws -> [Song]
        var setlists: @MainActor (_ startIndex: Int, _ pageSize: Int) async throws -> [Playlist]
        var publicPlaylists: @MainActor (_ startIndex: Int, _ pageSize: Int) async throws -> [Playlist]
        var latestSetlist: @MainActor () async throws -> KaraokeSetlist

        static var live: Requests {
            Requests(
                trending: { try await KaraokeAPIClient.trendingSongs(take: 20) },
                suggestions: { try await KaraokeAPIClient.songSuggestions(take: 20) },
                releases: { try await KaraokeAPIClient.latestReleases() },
                setlists: { startIndex, pageSize in
                    try await KaraokeAPIClient.playlists(
                        startIndex: startIndex,
                        pageSize: pageSize,
                        isSetlist: true,
                        sortDescending: true
                    )
                },
                publicPlaylists: { startIndex, pageSize in
                    try await KaraokeAPIClient.publicPlaylists(startIndex: startIndex, pageSize: pageSize)
                },
                latestSetlist: { try await KaraokeAPIClient.latestSetlist() }
            )
        }
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
    /// The setlist of the most recent karaoke stream, which New leads with as
    /// the website does.
    var latestSetlist: KaraokeSetlist?
    /// `latestSetlist` when it has songs to play.
    var playableLatestSetlist: KaraokeSetlist? {
        latestSetlist?.playlist.songListDTOs?.isEmpty == false ? latestSetlist : nil
    }
    /// Set once a load has finished, whether or not anything came back.
    private(set) var hasFinishedLoading = false
    /// The shelves are the copy saved on this device: the last load got
    /// nothing back, which almost always means no connection.
    private(set) var isShowingSavedContent = false

    /// Home has nothing from the network to show: every request failed (as
    /// when the app opens offline) or came back empty. Home used to render as
    /// a bare title with no way to tell why, and stayed that way until pulled
    /// to refresh.
    var homeIsEmpty: Bool {
        feedsAreEmpty && suggestions.isEmpty
    }

    /// The same for New, which does not show suggestions (suggestions alone
    /// would otherwise leave New blank while Home still had something) but
    /// does show the latest stream's setlist.
    var newIsEmpty: Bool {
        feedsAreEmpty && playableLatestSetlist == nil
    }

    /// Every feed Home and New share came back empty or failed.
    private var feedsAreEmpty: Bool {
        hasFinishedLoading && !isLoading && sharedShelvesAreEmpty
    }

    private var sharedShelvesAreEmpty: Bool {
        trending.isEmpty && recentPlaylists.isEmpty && newReleases.isEmpty
    }

    /// The newest release and the list it plays in, for the iPad Home hero's
    /// Play Latest row. Nil when New Releases didn't load, so the row isn't
    /// shown over a song from another list.
    var heroLatestRelease: (song: Song, context: [Song])? {
        guard let latestSingle else { return nil }
        return (latestSingle, latestSingleContext.isEmpty ? [latestSingle] : latestSingleContext)
    }
    // Bookkeeping the views never read; keep it out of the observation graph.
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var topPicksPage = 0
    @ObservationIgnored private let topPicksPageSize = 12
    @ObservationIgnored private var topPicksSource: HomeTopPicksSource = .setlists
    @ObservationIgnored private var dataGeneration = 0
    @ObservationIgnored private var homeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var topPicksLoadMoreTask: Task<Void, Never>?
    @ObservationIgnored private var latestSetlistTask: Task<Void, Never>?
    @ObservationIgnored private let requests: Requests
    @ObservationIgnored private let store: HomeFeedStore
    @ObservationIgnored private let accountIdentity: @Sendable () async -> HomeAccount?
    /// The account the current shelves were loaded for.
    @ObservationIgnored private var account: HomeAccount?
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []

    // No work in init. This type is held in `@State`, whose initial-value
    // expression is re-evaluated on every re-initialization of the owning view
    // struct (only the first instance is kept). `@StateObject` took an
    // @autoclosure and evaluated it once, so an init-time fetch was safe there
    // and is a request flood here. The fetch is driven from the view's .task
    // instead, and `hasLoaded` keeps it to one round trip. The session
    // observers are registered by the first load for the same reason.
    //
    // `store` is `.disabled` unless given: the app passes `.live`, and a model
    // made anywhere else (tests included) neither reads nor writes the saved
    // copy. UI test mode never uses it, so fixtures can't mix with it.
    init(
        requests: Requests = .live,
        store: HomeFeedStore = .disabled,
        accountIdentity: @escaping @Sendable () async -> HomeAccount? = HomeViewModel.liveAccountIdentity
    ) {
        self.requests = requests
        self.store = AppRuntime.isUITestMode ? .disabled : store
        self.accountIdentity = accountIdentity
    }

    func fetchHomeData(force: Bool = false) {
        if AppRuntime.isUITestMode {
            applyUITestFixture()
            return
        }

        if hasLoaded, !force { return }
        observeSessionChanges()
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
        // Saved top picks are one page with nothing to page from.
        canLoadMoreTopPicks = !isShowingSavedContent
        homeLoadTask = Task { [weak self] in
            guard let self else { return }
            let requests = requests
            // Read first, so an account change during the load can be told
            // apart from the account this load is for.
            let account = await accountIdentity()
            guard !Task.isCancelled, dataGeneration == generation else { return }
            self.account = account
            async let trendingResult = try? requests.trending()
            async let suggestionsResult = try? requests.suggestions()
            async let topPicksResult = fetchTopPicks(startIndex: 0)
            async let releasesResult = try? requests.releases()

            let (loadedTrending, suggestionsAnswer, loadedTopPicks, loadedReleases) = await (
                trendingResult,
                suggestionsResult,
                topPicksResult,
                releasesResult
            )
            // The token can change while the requests run, before the session
            // notification arrives, so Made for You may be either account's:
            // it is neither shown nor saved. A read that can't tell keeps it.
            let accountNow = await accountIdentity()
            guard !Task.isCancelled, dataGeneration == generation else { return }
            let accountChanged = accountNow != nil && accountNow != account
            let loadedSuggestions = accountChanged ? nil : suggestionsAnswer

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

            let fresh = Self.freshSnapshot(
                trending: loadedTrending,
                releases: loadedReleases,
                topPicks: loadedTopPicks.playlists,
                topPicksSource: loadedTopPicks.source
            )
            let freshSuggestions = loadedSuggestions?.isEmpty == false ? loadedSuggestions : nil
            // Anything that loaded means the network is back: what's on screen
            // is no longer only the saved copy.
            if !fresh.isEmpty || freshSuggestions != nil { isShowingSavedContent = false }
            save(fresh, suggestions: freshSuggestions, for: account)
            // Nothing to show for Home and New, or nothing new while the
            // saved copy is up: fall back to (or stay on) the saved copy.
            let loadedNothing = fresh.isEmpty && freshSuggestions == nil
            if sharedShelvesAreEmpty || (isShowingSavedContent && loadedNothing) {
                guard await restoreSavedContent(for: account, generation: generation) else { return }
            }

            hasFinishedLoading = true
            isLoading = false
            homeLoadTask = nil
            // Let the next appearance or activation try again instead of
            // treating a load that left a screen empty, or showing only what
            // was saved, as done.
            if feedsAreEmpty || isShowingSavedContent { hasLoaded = false }
        }
        loadLatestSetlist(generation: generation)
    }

    /// Writes what a load got back into the saved copy. Only content that
    /// loaded is written; "Made for You" only for a known, signed-in account.
    private func save(_ fresh: HomeFeedSnapshot, suggestions: [Song]?, for account: HomeAccount?) {
        let store = store
        if !fresh.isEmpty {
            Task { await store.savePublic(fresh) }
        }
        if let suggestions, let key = account?.suggestionsKey {
            Task { await store.saveSuggestions(key, HomeSuggestionsSnapshot(songs: suggestions)) }
        }
    }

    /// Fills the empty shelves from the copy saved on this device. Returns
    /// false when a newer load took over while the copy was being read.
    private func restoreSavedContent(for account: HomeAccount?, generation: Int) async -> Bool {
        let store = store
        async let savedFeed = store.loadPublic()
        var savedSuggestions: HomeSuggestionsSnapshot?
        if suggestions.isEmpty, let key = account?.suggestionsKey {
            savedSuggestions = await store.loadSuggestions(key)
        }
        let saved = await savedFeed
        guard !Task.isCancelled, dataGeneration == generation else { return false }

        var restored = false
        if let songs = saved?.trending {
            trending = songs
            restored = true
        }
        if let songs = saved?.newReleases {
            newReleases = songs
            latestSingle = songs.first
            latestSingleContext = songs
            restored = true
        }
        if let playlists = saved?.topPicks {
            recentPlaylists = playlists
            topPicksSource = saved?.topPicksSource ?? .setlists
            canLoadMoreTopPicks = false
            restored = true
        }
        if latestSetlist == nil, let setlist = saved?.latestSetlist?.setlist {
            latestSetlist = setlist
            restored = true
        }
        if let songs = savedSuggestions?.songs {
            suggestions = songs
            restored = true
        }
        if restored {
            isShowingSavedContent = true
            DebugLogger.log("Home is showing the copy saved on this device", category: .cache)
        }
        return true
    }

    // MARK: - Account changes

    /// Home used to keep the previous account's "Made for You" on screen
    /// after a sign-in, sign-out or account switch, because nothing reloaded
    /// it. Registered by the first load, not in `init`.
    private func observeSessionChanges() {
        guard sessionObservers.isEmpty else { return }
        sessionObservers = [
            WatchSessionLink.sessionChanged,
            UIApplication.protectedDataDidBecomeAvailableNotification,
        ].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.accountMayHaveChanged() }
            }
        }
    }

    /// Reloads for the new account when it changed, or when the first load
    /// couldn't tell the account (locked Keychain) and it can be told now.
    /// Its first act is a new generation, so a response still on its way for
    /// the previous account is dropped, and never shown or saved under the
    /// new one. An account that still can't be told changes nothing.
    func accountMayHaveChanged() async {
        guard let identity = await accountIdentity(), identity != account else { return }
        self.account = identity
        dataGeneration += 1
        suggestions = []
        fetchHomeData(force: true)
    }

    /// Loaded on its own: it only feeds New's first card, so a slow request
    /// must not keep Home and New on their skeletons. Like the shelves, a
    /// failed refresh keeps the setlist already shown.
    private func loadLatestSetlist(generation: Int) {
        latestSetlistTask?.cancel()
        let requests = requests
        latestSetlistTask = Task { [weak self] in
            let loaded = try? await requests.latestSetlist()
            guard !Task.isCancelled, let self, dataGeneration == generation else { return }
            if let loaded {
                latestSetlist = loaded
                save(HomeFeedSnapshot(latestSetlist: CachedSetlist(loaded)), suggestions: nil, for: nil)
            }
            latestSetlistTask = nil
        }
    }

    /// Retries a load that left Home or New with nothing to show, or with
    /// only the saved copy. Called when the app becomes active, which is
    /// usually when a connection has come back. The latest setlist alone
    /// doesn't count: Home doesn't show it.
    func retryIfLoadFailed() {
        guard feedsAreEmpty || isShowingSavedContent, homeLoadTask == nil else { return }
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
        let requests = requests
        topPicksLoadMoreTask = Task { [weak self] in
            let playlists: [Playlist] = switch source {
            case .setlists:
                await (try? requests.setlists(startIndex, pageSize)) ?? []
            case .publicPlaylists:
                await (try? requests.publicPlaylists(startIndex, pageSize)) ?? []
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
    ) async -> (source: HomeTopPicksSource, playlists: [Playlist]?) {
        let pageSize = topPicksPageSize
        let setlists = await (try? requests.setlists(startIndex, pageSize)) ?? []
        if !setlists.isEmpty {
            return (.setlists, setlists)
        }

        let fallback = try? await requests.publicPlaylists(startIndex, pageSize)
        return (.publicPlaylists, fallback)
    }

    private func applyUITestFixture() {
        hasLoaded = true
        isLoading = false
        isLoadingMoreTopPicks = false
        canLoadMoreTopPicks = false
        topPicksSource = .setlists
        isShowingSavedContent = ProcessInfo.processInfo.arguments.contains("-UITestHomeSavedContent")

        let fixtureSongs = Self.fixtureSongs
        // More songs than New's five-row preview shows, so See All has more.
        trending = Array(fixtureSongs.suffix(4)) + Array(fixtureSongs.prefix(2))
        suggestions = Array(fixtureSongs.prefix(4))
        newReleases = fixtureSongs
        latestSingle = fixtureSongs.first
        latestSingleContext = fixtureSongs
        // In reverse, so its order differs from New Releases.
        latestSetlist = KaraokeSetlist(
            playlist: UITestFixtures.playlist(
                id: "ui-home-setlist-latest",
                name: "Neuro Karaoke - November 1, 2026 Setlist",
                songs: fixtureSongs.reversed()
            ),
            streamDay: DateComponents(year: 2026, month: 11, day: 1),
            totalDuration: 1260
        )
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

    isolated deinit {
        homeLoadTask?.cancel()
        topPicksLoadMoreTask?.cancel()
        latestSetlistTask?.cancel()
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
    }
}
