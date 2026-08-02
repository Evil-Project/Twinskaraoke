import Foundation
import Observation

/// The signed-in listener's own playlists.
///
/// Read-only on the watch: creating playlists and adding songs stay on the
/// phone, so this deliberately does not mirror `UserPlaylistsManager`. Results
/// are mapped to `Playlist` so the existing watch grid and detail views work
/// unchanged.
@MainActor
@Observable
final class UserPlaylistsViewModel {
    var playlists: [Playlist] = []
    var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    var loadError: String?

    func fetch(force: Bool = false) {
        guard !isLoading else { return }
        guard force || playlists.isEmpty else { return }
        guard CredentialStore.isAuthenticated else {
            playlists = []
            return
        }
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let request = try KaraokeAPIClient.request(path: "/api/user/playlists")
                let data = try await KaraokeAPIClient.data(for: request)
                playlists = try JSONDecoder()
                    .decode([UserPlaylist].self, from: data)
                    .map { $0.asPlaylist() }
            } catch {
                loadError = "Check your connection and try again."
            }
        }
    }

    /// Called when the watch loses its session, so another account's playlists
    /// can't linger on screen.
    func reset() {
        playlists = []
        loadError = nil
    }
}
