import Foundation
import Observation

@MainActor
@Observable
final class PlaylistsViewModel {
    var playlists: [Playlist] = []
    var favoriteSongs: [Song] = []
    var isLoading = false
    var isLoadingFavorites = false
    /// Server + saved + user playlists, merged and deduped once per source
    /// change instead of on every view body evaluation.
    private(set) var combinedPlaylists: [Playlist] = []
    @ObservationIgnored private var hasLoadedPlaylists = false
    @ObservationIgnored private var hasLoadedFavoriteSongs = false
    @ObservationIgnored private var sourceObservation: ObservationToken?
    @ObservationIgnored private var playlistsTask: Task<Void, Never>?
    @ObservationIgnored private var favoriteSongsTask: Task<Void, Never>?

    init() {
        // Replaces the Merge5 of `$playlists`, `$favoriteSongs`, the two stores
        // and `$favoriteIDs`. `observeContinuously` already hops to the next
        // main-actor turn before calling back, which is what the old
        // `.receive(on: DispatchQueue.main)` was there for — observation fires
        // from willSet, so the recompute must not read pre-write values.
        sourceObservation = observeContinuously({
            _ = self.playlists
            _ = self.favoriteSongs
            _ = SavedPlaylistsStore.shared.playlists
            _ = UserPlaylistsManager.shared.playlists
            _ = FavoritesManager.shared.favoriteIDs
        }, onChange: { [weak self] in
            self?.recomputeCombinedPlaylists()
        })
        recomputeCombinedPlaylists()
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

    private func recomputeCombinedPlaylists() {
        let all = allPlaylists(saved: SavedPlaylistsStore.shared.playlists)
        let existingIDs = Set(all.map(\.id))
        let uniqueUser = UserPlaylistsManager.shared.playlists
            .map { $0.asPlaylist() }
            .filter { !existingIDs.contains($0.id) }
        let next = uniqueUser + all
        // Guarded because @Observable publishes on every write, including one
        // that stores an identical value, and `favoritesPlaylist` builds a fresh
        // struct on each call — so an unguarded assignment re-renders the whole
        // library on any unrelated source change. Combine's removeDuplicates
        // used to absorb this.
        guard next != combinedPlaylists else { return }
        combinedPlaylists = next
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

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until both the playlists and the favorite songs have finished loading.
    func refreshAll() async {
        fetchPlaylists(force: true)
        fetchFavoriteSongs(force: true)
        await playlistsTask?.value
        await favoriteSongsTask?.value
    }

    func fetchPlaylists(force: Bool = false) {
        guard !isLoading else { return }
        guard force || !hasLoadedPlaylists else { return }
        isLoading = true
        playlistsTask = Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let loaded = try await KaraokeAPIClient.playlists(
                    startIndex: 0,
                    pageSize: 25,
                    isSetlist: false,
                    sortDescending: false
                )
                playlists = loaded
                hasLoadedPlaylists = true
                RecentlyAddedTracker.shared.registerIfNew(loaded.map(\.id))
            } catch {
                if force || playlists.isEmpty {
                    playlists = []
                }
            }
        }
    }

    func fetchFavoriteSongs(force: Bool = false) {
        guard !isLoadingFavorites else { return }
        guard force || !hasLoadedFavoriteSongs else { return }
        isLoadingFavorites = true
        favoriteSongsTask = Task { [weak self] in
            guard let self else { return }
            defer { isLoadingFavorites = false }
            do {
                favoriteSongs = try await KaraokeAPIClient.favoriteSongs()
                hasLoadedFavoriteSongs = true
            } catch {
                if force || favoriteSongs.isEmpty {
                    favoriteSongs = []
                }
            }
        }
    }
}
