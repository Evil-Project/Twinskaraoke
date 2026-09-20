import Foundation
import Observation
@MainActor
@Observable
final class TVUserPlaylistsManager {
    static let shared = TVUserPlaylistsManager()

    private(set) var playlists: [UserPlaylist] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    @ObservationIgnored private var loadedToken: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private init() {
        NotificationCenter.default.addObserver(
            forName: .karaokeSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clear()
            }
        }
    }

    var isSignedIn: Bool {
        CredentialStore.isAuthenticated
    }
    func loadIfNeeded() {
        guard let token = CredentialStore.token, !token.isEmpty else {
            clear()
            return
        }
        guard loadedToken != token, !isLoading else { return }
        load()
    }

    func load() {
        guard let token = CredentialStore.token, !token.isEmpty else {
            clear()
            return
        }

        loadTask?.cancel()
        generation += 1
        let generation = generation
        isLoading = true
        loadError = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == generation {
                    self.isLoading = false
                    self.loadTask = nil
                }
            }
            do {
                let request = try KaraokeAPIClient.request(path: "/api/user/playlists")
                let data = try await KaraokeAPIClient.data(for: request)
                try Task.checkCancellation()
                guard self.generation == generation, CredentialStore.token == token else { return }
                self.playlists = try JSONDecoder().decode([UserPlaylist].self, from: data)
                self.loadedToken = token
            } catch {
                guard !Task.isCancelled, self.generation == generation,
                      CredentialStore.token == token else { return }
                DebugLogger.log(
                    "User playlists load failed: \(String(describing: error))",
                    category: .network
                )
                self.loadError = String(localized: "Check your connection and try again.")
            }
        }
    }
    func create(name: String, description: String?, isPublic: Bool) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }

        var body: [String: Any] = [
            "Name": name,
            "IsPublic": isPublic,
            "IsSetList": false,
        ]
        if let description, !description.isEmpty {
            body["Description"] = description
        }

        do {
            let request = try KaraokeAPIClient.jsonRequest(path: "/api/playlist/save", body: body)
            _ = try await KaraokeAPIClient.data(for: request)
        } catch {
            DebugLogger.log(
                "Playlist create failed: \(String(describing: error))",
                category: .network
            )
            return false
        }

        load()
        return true
    }
    func addSong(_ songID: String, to playlistID: String) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }

        do {
            var request = try KaraokeAPIClient.request(
                pathSegments: ["api", "user", "playlists", playlistID],
                queryItems: [URLQueryItem(name: "songId", value: songID)]
            )
            request.httpMethod = "PUT"
            _ = try await KaraokeAPIClient.data(for: request)
        } catch {
            DebugLogger.log(
                "Add song \(songID) to playlist \(playlistID) failed: \(String(describing: error))",
                category: .network
            )
            return false
        }

        await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
        load()
        return true
    }
    func removeSong(_ songID: String, from playlistID: String) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }

        do {
            var request = try KaraokeAPIClient.request(
                pathSegments: ["api", "playlist", playlistID, "song", songID]
            )
            request.httpMethod = "DELETE"
            _ = try await KaraokeAPIClient.data(for: request)
        } catch KaraokeAPIClient.APIError.httpStatus(404) {
        } catch {
            DebugLogger.log(
                "Remove song \(songID) from playlist \(playlistID) failed: \(String(describing: error))",
                category: .network
            )
            return false
        }
        await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
        load()
        return true
    }

    func clear() {
        loadTask?.cancel()
        loadTask = nil
        generation += 1
        playlists = []
        loadedToken = nil
        loadError = nil
        isLoading = false
    }
}
