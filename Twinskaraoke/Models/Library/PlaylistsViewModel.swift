import Combine
import Foundation

@MainActor
final class PlaylistsViewModel: ObservableObject {
    typealias PlaylistLoader = @Sendable () async throws -> [Playlist]
    typealias FavoriteSongsLoader = @Sendable () async throws -> [Song]
    typealias SessionScopeProvider = @MainActor () -> UserSessionScope

    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var favoriteSongs: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingFavorites = false

    private var hasLoadedPlaylists = false
    private var hasLoadedFavoriteSongs = false
    private var playlistTask: Task<Void, Never>?
    private var favoriteSongsTask: Task<Void, Never>?
    private var playlistGeneration: UInt64 = 0
    private var favoriteSongsGeneration: UInt64 = 0
    private var sessionGeneration: UInt64 = 0
    private var needsFavoriteSongsReload = false
    private var activeSessionScope: UserSessionScope
    private let playlistLoader: PlaylistLoader
    private let favoriteSongsLoader: FavoriteSongsLoader
    private let sessionScopeProvider: SessionScopeProvider

    init(
        playlistLoader: @escaping PlaylistLoader = {
            try await KaraokeAPIClient.playlists(
                startIndex: 0,
                pageSize: 25,
                isSetlist: false,
                sortDescending: false
            )
        },
        favoriteSongsLoader: @escaping FavoriteSongsLoader = {
            try await KaraokeAPIClient.favoriteSongs()
        },
        sessionScopeProvider: @escaping SessionScopeProvider = { UserSessionScope.current }
    ) {
        self.playlistLoader = playlistLoader
        self.favoriteSongsLoader = favoriteSongsLoader
        self.sessionScopeProvider = sessionScopeProvider
        activeSessionScope = sessionScopeProvider()
    }

    deinit {
        playlistTask?.cancel()
        favoriteSongsTask?.cancel()
    }

    var favoritesPlaylist: Playlist {
        let favoriteCount = max(favoriteSongs.count, FavoritesManager.shared.favoriteIDs.count)
        return Playlist(
            id: Playlist.favoritesID,
            name: "Favourite Songs",
            songCount: favoriteCount,
            mosaicMedia: nil,
            songListDTOs: favoriteSongs
        )
    }

    func allPlaylists(saved: [Playlist]) -> [Playlist] {
        let serverIDs = Set(playlists.map(\.id))
        let localOnly = saved.filter { !serverIDs.contains($0.id) }
        return [favoritesPlaylist] + playlists + localOnly
    }

    func recentlyAddedPlaylists(saved: [Playlist]) -> [Playlist] {
        let serverIDs = Set(playlists.map(\.id))
        let localOnly = saved.filter { !serverIDs.contains($0.id) }
        let combined = (playlists + localOnly).sorted { lhs, rhs in
            RecentlyAddedTracker.shared.date(for: lhs.id)
                > RecentlyAddedTracker.shared.date(for: rhs.id)
        }
        return [favoritesPlaylist] + combined
    }

    func fetchPlaylists(force: Bool = false) {
        if isLoading {
            guard force else { return }
            cancelPlaylistLoad()
        }
        guard force || !hasLoadedPlaylists else { return }

        playlistGeneration &+= 1
        let requestGeneration = playlistGeneration
        let playlistLoader = playlistLoader
        isLoading = true

        playlistTask = Task { @MainActor [weak self, playlistLoader] in
            do {
                let loaded = try await playlistLoader()
                guard let self,
                      requestGeneration == playlistGeneration,
                      !Task.isCancelled
                else { return }

                playlists = loaded
                hasLoadedPlaylists = true
                isLoading = false
                playlistTask = nil
                RecentlyAddedTracker.shared.registerIfNew(loaded.map(\.id))
            } catch {
                guard let self,
                      requestGeneration == playlistGeneration,
                      !Task.isCancelled
                else { return }

                isLoading = false
                playlistTask = nil
            }
        }
    }

    func fetchFavoriteSongs(force: Bool = false) {
        synchronizeSessionIfNeeded()
        if isLoadingFavorites {
            if force {
                needsFavoriteSongsReload = true
            }
            return
        }
        guard force || !hasLoadedFavoriteSongs else { return }

        favoriteSongsGeneration &+= 1
        let requestGeneration = favoriteSongsGeneration
        let requestSessionGeneration = sessionGeneration
        let sessionScope = activeSessionScope
        let favoriteSongsLoader = favoriteSongsLoader
        isLoadingFavorites = true

        favoriteSongsTask = Task { @MainActor [weak self, favoriteSongsLoader] in
            do {
                let loaded = try await favoriteSongsLoader()
                guard let self else { return }
                synchronizeSessionIfNeeded()
                guard isCurrentFavoriteSongsLoad(
                    requestGeneration: requestGeneration,
                    sessionGeneration: requestSessionGeneration,
                    sessionScope: sessionScope
                ) else { return }

                favoriteSongs = loaded
                hasLoadedFavoriteSongs = true
                isLoadingFavorites = false
                favoriteSongsTask = nil
                startPendingFavoriteSongsReloadIfNeeded()
            } catch {
                guard let self else { return }
                synchronizeSessionIfNeeded()
                guard isCurrentFavoriteSongsLoad(
                    requestGeneration: requestGeneration,
                    sessionGeneration: requestSessionGeneration,
                    sessionScope: sessionScope
                ) else { return }

                isLoadingFavorites = false
                favoriteSongsTask = nil
                startPendingFavoriteSongsReloadIfNeeded()
            }
        }
    }

    func refresh() async {
        fetchPlaylists(force: true)
        let activePlaylistTask = playlistTask
        fetchFavoriteSongs(force: true)

        await activePlaylistTask?.value
        while let activeFavoriteSongsTask = favoriteSongsTask {
            await activeFavoriteSongsTask.value
        }
    }

    func sessionDidChange() {
        resetFavoriteSongs(for: sessionScopeProvider())
    }

    private func synchronizeSessionIfNeeded() {
        let currentScope = sessionScopeProvider()
        guard currentScope != activeSessionScope else { return }
        resetFavoriteSongs(for: currentScope)
    }

    private func resetFavoriteSongs(for sessionScope: UserSessionScope) {
        sessionGeneration &+= 1
        activeSessionScope = sessionScope
        cancelFavoriteSongsLoad()
        favoriteSongs = []
        hasLoadedFavoriteSongs = false
    }

    private func startPendingFavoriteSongsReloadIfNeeded() {
        guard needsFavoriteSongsReload else { return }
        needsFavoriteSongsReload = false
        fetchFavoriteSongs(force: true)
    }

    private func cancelPlaylistLoad() {
        playlistGeneration &+= 1
        playlistTask?.cancel()
        playlistTask = nil
        isLoading = false
    }

    private func cancelFavoriteSongsLoad() {
        favoriteSongsGeneration &+= 1
        favoriteSongsTask?.cancel()
        favoriteSongsTask = nil
        isLoadingFavorites = false
        needsFavoriteSongsReload = false
    }

    private func isCurrentFavoriteSongsLoad(
        requestGeneration: UInt64,
        sessionGeneration: UInt64,
        sessionScope: UserSessionScope
    ) -> Bool {
        requestGeneration == favoriteSongsGeneration
            && sessionGeneration == self.sessionGeneration
            && sessionScope == activeSessionScope
            && !Task.isCancelled
    }
}
