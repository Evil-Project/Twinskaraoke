import Foundation
import Observation

@MainActor
@Observable
final class UserPlaylistsManager {
    static let shared = UserPlaylistsManager()

    private(set) var playlists: [UserPlaylist] = []
    private(set) var isLoading = false

    /// Playlists belong to the account: creating one or adding to one needs a
    /// signed-in session. Stored so views update, refreshed on the paths that
    /// sign-in and sign-out already take (`fetchPlaylists`, `clear`).
    private(set) var isAvailable = CredentialStore.isAuthenticated

    private var loaded = false
    private var stateGeneration = 0
    private var forcedReloadPending = false

    @ObservationIgnored private var songCountGenerations: [String: Int] = [:]

    @ObservationIgnored private let songMutations = PlaylistSongMutationCoordinator()

    func loadIfNeeded() {
        fetchPlaylists(force: false)
    }

    func fetchPlaylists(force: Bool = true) {
        refreshAvailability()
        guard !isLoading else {
            if force {
                forcedReloadPending = true
            }
            return
        }
        guard force || !loaded else { return }
        if case .unavailable = CredentialStore.readToken() { return }
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

        let mutation = PlaylistSongMutationCoordinator.Key(playlistID: playlistID, songID: songID, adding: true)
        guard songMutations.begin(mutation, completion: completion) else { return }

        Task {
            guard var req = try? KaraokeAPIClient.request(
                pathSegments: ["api", "user", "playlists", playlistID],
                queryItems: [URLQueryItem(name: "songId", value: songID)]
            ) else {
                songMutations.finish(mutation, success: false)
                return
            }
            req.httpMethod = "PUT"
            let ok = (try? await KaraokeAPIClient.data(for: req)) != nil
            if ok {
                PlaylistSongCountStore.shared.invalidate(playlistID: playlistID)
                await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
                await refreshSongCount(forPlaylist: playlistID)
            }
            songMutations.finish(mutation, success: ok)
        }
    }
    func removeSong(
        _ songID: String,
        fromPlaylist playlistID: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard CredentialStore.isAuthenticated else {
            completion?(false)
            return
        }

        let mutation = PlaylistSongMutationCoordinator.Key(playlistID: playlistID, songID: songID, adding: false)
        guard songMutations.begin(mutation, completion: completion) else { return }

        Task {
            guard var req = try? KaraokeAPIClient.request(
                pathSegments: ["api", "playlist", playlistID, "song", songID]
            ) else {
                songMutations.finish(mutation, success: false)
                return
            }
            req.httpMethod = "DELETE"
            let ok: Bool
            do {
                _ = try await KaraokeAPIClient.data(for: req)
                ok = true
            } catch KaraokeAPIClient.APIError.httpStatus(404) {
                ok = true
            } catch {
                ok = false
            }
            if ok {
                PlaylistSongCountStore.shared.invalidate(playlistID: playlistID)
                await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
                await refreshSongCount(forPlaylist: playlistID)
            }
            songMutations.finish(mutation, success: ok)
        }
    }
    func moveSong(
        _ songID: String,
        from oldOrder: Int,
        to newOrder: Int,
        inPlaylist playlistID: String
    ) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }
        guard let req = try? KaraokeAPIClient.jsonArrayRequest(
            pathSegments: ["api", "user", "playlists", playlistID, "save-order"],
            body: KaraokeAPIClient.songMovePayload(songID: songID, from: oldOrder, to: newOrder)
        ) else { return false }
        guard (try? await KaraokeAPIClient.data(for: req)) != nil else { return false }
        await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
        return true
    }

    /// Reconciles successful writes with the server count, ignoring older concurrent refreshes.
    private func refreshSongCount(forPlaylist playlistID: String) async {
        let generation = stateGeneration
        songCountGenerations[playlistID, default: 0] += 1
        let countGeneration = songCountGenerations[playlistID]
        do {
            var request = try KaraokeAPIClient.request(pathSegments: ["api", "playlist", playlistID])
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let data = try await KaraokeAPIClient.data(for: request)
            let detail = try JSONDecoder().decode(PlaylistDetail.self, from: data)
            guard generation == stateGeneration, countGeneration == songCountGenerations[playlistID] else { return }
            setSongCount(forPlaylist: playlistID, count: detail.songListDTOs.count)
        } catch {
            // A successful idempotent write or DELETE 404 does not prove a count delta.
            // Retain the last count until the playlist list can be refreshed.
            guard generation == stateGeneration, countGeneration == songCountGenerations[playlistID] else { return }
            fetchPlaylists()
        }
    }

    /// Replaces only the count while preserving the playlist metadata.
    private func setSongCount(forPlaylist playlistID: String, count: Int) {
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
            songCount: max(0, count),
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

    private func refreshAvailability() {
        let available = CredentialStore.isAuthenticated
        if isAvailable != available { isAvailable = available }
    }

    func clear() {
        refreshAvailability()
        stateGeneration += 1
        playlists = []
        loaded = false
        isLoading = false
        forcedReloadPending = false
    }
}

/// Shares one in-flight mutation result with all windows requesting the same action.
@MainActor
final class PlaylistSongMutationCoordinator {
    struct Key: Hashable {
        let playlistID: String
        let songID: String
        let adding: Bool
    }

    private var completions: [Key: [(Bool) -> Void]] = [:]

    /// Returns whether the caller should send the request; duplicate callers share its result.
    func begin(_ key: Key, completion: ((Bool) -> Void)?) -> Bool {
        let alreadyRunning = completions[key] != nil
        completions[key, default: []].append(completion ?? { _ in })
        return !alreadyRunning
    }

    /// Clears the pending request before notifying all callers, allowing later retries.
    func finish(_ key: Key, success: Bool) {
        let callbacks = completions.removeValue(forKey: key) ?? []
        callbacks.forEach { $0(success) }
    }
}
