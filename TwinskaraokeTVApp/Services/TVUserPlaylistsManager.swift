import Foundation
import Observation

/// The signed-in user's own playlists, from `/api/user/playlists`.
///
/// Shared rather than per-view state because the grid and the create sheet
/// presented over it both work on the same list — a playlist saved in the sheet
/// has to land in the grid behind it without the user refreshing anything.
///
/// This is the tvOS counterpart to the iOS `UserPlaylistsManager`; it stays a
/// separate type because that one carries iOS-only collaborators (the
/// recently-added tracker, the song-count store) that have no tvOS surface.
@MainActor
@Observable
final class TVUserPlaylistsManager {
    static let shared = TVUserPlaylistsManager()

    private(set) var playlists: [UserPlaylist] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    /// The token the current list was fetched with. Compared on each appearance
    /// so signing out and back in as someone else refetches rather than leaving
    /// the previous account's playlists on screen.
    @ObservationIgnored private var loadedToken: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Bumped per load so a cancelled fetch resuming late can't clear the
    /// loading flag out from under the one that replaced it.
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

    /// Call on every appearance: loads on first sight of a signed-in session,
    /// refetches when the account changed, and clears after a sign-out.
    func loadIfNeeded() {
        guard let token = CredentialStore.token, !token.isEmpty else {
            clear()
            return
        }
        // A failed load leaves `loadedToken` nil, so the next appearance retries
        // instead of showing a stale error over an account we never read — but
        // not while that retry is still in flight, or switching tabs during the
        // first load restarts it each time.
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
                }
            }
            do {
                let request = try KaraokeAPIClient.request(path: "/api/user/playlists")
                let data = try await KaraokeAPIClient.data(for: request)
                guard self.generation == generation else { return }
                self.playlists = try JSONDecoder().decode([UserPlaylist].self, from: data)
                self.loadedToken = token
            } catch {
                guard self.generation == generation else { return }
                self.loadError = "Check your connection and try again."
            }
        }
    }

    /// Creates a playlist and reloads the list so the caller's grid shows it.
    /// Returns `false` if the save didn't reach the server.
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
            return false
        }

        load()
        return true
    }

    /// Adds one song to one of the user's playlists.
    /// Returns `false` if the server didn't accept it.
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
            return false
        }

        await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
        load()
        return true
    }

    /// Removes one song from one of the user's playlists.
    /// Returns `false` if the server didn't accept the removal.
    func removeSong(_ songID: String, from playlistID: String) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }

        do {
            var request = try KaraokeAPIClient.request(
                pathSegments: ["api", "playlist", playlistID, "song", songID]
            )
            request.httpMethod = "DELETE"
            _ = try await KaraokeAPIClient.data(for: request)
        } catch {
            return false
        }

        // The detail payload is cached for 60s, and the grid caption shows a
        // song count from the list endpoint — both would otherwise still show
        // the removed song after the user backs out and comes straight back in.
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
