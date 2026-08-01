import Combine
import Foundation

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var favoriteSongs: [Song] = []
    @Published var isLoading = false
    @Published var isLoadingFavorites = false
    /// Server + saved + user playlists, merged and deduped once per source
    /// change instead of on every view body evaluation.
    @Published private(set) var combinedPlaylists: [Playlist] = []
    private var hasLoadedPlaylists = false
    private var hasLoadedFavoriteSongs = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        let sourceChanges = Publishers.Merge4(
            $playlists.map { _ in },
            $favoriteSongs.map { _ in },
            SavedPlaylistsStore.shared.$playlists.map { _ in },
            UserPlaylistsManager.shared.$playlists.map { _ in }
        )
        .merge(with: FavoritesManager.shared.$favoriteIDs.map { _ in })
        // @Published fires from willSet; hop one main-queue pass so the
        // recompute below reads the already-updated values.
        .receive(on: DispatchQueue.main)
        sourceChanges
            .sink { [weak self] in self?.recomputeCombinedPlaylists() }
            .store(in: &cancellables)
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
        combinedPlaylists = uniqueUser + all
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
        guard !isLoading else { return }
        guard force || !hasLoadedPlaylists else { return }
        isLoading = true
        Task { [weak self] in
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
        Task { [weak self] in
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
