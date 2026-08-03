import Foundation
import Observation

@MainActor
@Observable
final class UserPlaylistsManager {
    static let shared = UserPlaylistsManager()

    private(set) var playlists: [UserPlaylist] = []
    private(set) var isLoading = false

    private var loaded = false
    private var stateGeneration = 0
    private var forcedReloadPending = false

    func loadIfNeeded() {
        fetchPlaylists(force: false)
    }

    func fetchPlaylists(force: Bool = true) {
        guard !isLoading else {
            if force {
                forcedReloadPending = true
            }
            return
        }
        guard force || !loaded else { return }
        guard CredentialStore.isAuthenticated else {
            playlists = []
            loaded = false
            return
        }

        isLoading = true
        let generation = stateGeneration
        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.stateGeneration == generation {
                    self.isLoading = false
                    if self.forcedReloadPending {
                        self.forcedReloadPending = false
                        self.fetchPlaylists(force: true)
                    }
                }
            }

            guard let req = try? KaraokeAPIClient.request(path: "/api/user/playlists"),
                  let data = try? await KaraokeAPIClient.data(for: req),
                  let decoded = try? JSONDecoder().decode([UserPlaylist].self, from: data)
            else { return }
            guard self.stateGeneration == generation else { return }

            self.playlists = decoded
            self.loaded = true
            RecentlyAddedTracker.shared.registerIfNew(decoded.map(\.id))
        }
    }

    func createPlaylist(
        name: String,
        description: String? = nil,
        isPublic: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard CredentialStore.isAuthenticated else {
            completion?(false)
            return
        }

        Task {
            var body: [String: Any] = [
                "Name": name,
                "IsPublic": isPublic,
                "IsSetList": false,
            ]
            if let description, !description.isEmpty {
                body["Description"] = description
            }

            guard let req = try? KaraokeAPIClient.jsonRequest(path: "/api/playlist/save", body: body),
                  (try? await KaraokeAPIClient.data(for: req)) != nil
            else {
                completion?(false)
                return
            }

            await MainActor.run { self.fetchPlaylists() }
            completion?(true)
        }
    }

    func addSong(
        _ songID: String,
        toPlaylist playlistID: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard CredentialStore.isAuthenticated else {
            completion?(false)
            return
        }

        Task {
            guard var req = try? KaraokeAPIClient.request(
                pathSegments: ["api", "user", "playlists", playlistID],
                queryItems: [URLQueryItem(name: "songId", value: songID)]
            ) else {
                completion?(false)
                return
            }
            req.httpMethod = "PUT"
            let ok = (try? await KaraokeAPIClient.data(for: req)) != nil
            if ok {
                adjustSongCount(forPlaylist: playlistID, by: 1)
                PlaylistSongCountStore.shared.invalidate(playlistID: playlistID)
                await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
            }
            completion?(ok)
        }
    }

    /// Note the different route shape from `addSong`: adding is
    /// `PUT /api/user/playlists/{id}?songId=`, but the only method that path
    /// accepts is PUT — removal lives on `/api/playlist/{id}/song/{songId}`,
    /// which accepts DELETE alone.
    func removeSong(
        _ songID: String,
        fromPlaylist playlistID: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard CredentialStore.isAuthenticated else {
            completion?(false)
            return
        }

        Task {
            guard var req = try? KaraokeAPIClient.request(
                pathSegments: ["api", "playlist", playlistID, "song", songID]
            ) else {
                completion?(false)
                return
            }
            req.httpMethod = "DELETE"
            let ok = (try? await KaraokeAPIClient.data(for: req)) != nil
            if ok {
                adjustSongCount(forPlaylist: playlistID, by: -1)
                PlaylistSongCountStore.shared.invalidate(playlistID: playlistID)
                await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
            }
            completion?(ok)
        }
    }

    private func adjustSongCount(forPlaylist playlistID: String, by delta: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let playlist = playlists[index]
        playlists[index] = UserPlaylist(
            id: playlist.id,
            name: playlist.name,
            description: playlist.description,
            createdBy: playlist.createdBy,
            updatedBy: playlist.updatedBy,
            media: playlist.media,
            createdAt: playlist.createdAt,
            updatedAt: playlist.updatedAt,
            totalDuration: playlist.totalDuration,
            songCount: max(0, playlist.songCount + delta),
            playCount: playlist.playCount,
            favoriteCount: playlist.favoriteCount,
            playlistType: playlist.playlistType,
            songListDTOs: playlist.songListDTOs,
            mosaicMedia: playlist.mosaicMedia,
            genres: playlist.genres,
            editable: playlist.editable,
            deletable: playlist.deletable,
            isPublic: playlist.isPublic,
            isSetList: playlist.isSetList,
            setListDate: playlist.setListDate
        )
    }

    func clear() {
        stateGeneration += 1
        playlists = []
        loaded = false
        isLoading = false
        forcedReloadPending = false
    }
}
