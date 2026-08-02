import Foundation
import Observation

@MainActor
@Observable
final class PlaylistsViewModel {
    var playlists: [Playlist] = []
    var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    var loadError: String?

    func fetchMusic() {
        guard !isLoading, playlists.isEmpty else { return }
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                playlists = try await KaraokeAPIClient.playlists(
                    startIndex: 0,
                    pageSize: 15,
                    isSetlist: true,
                    sortDescending: false
                )
            } catch {
                loadError = "Check your connection and try again."
            }
        }
    }
}
