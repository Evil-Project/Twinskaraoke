import Combine
import Foundation

/// The signed-in listener's favorite songs.
///
/// Reads through `KaraokeAPIClient.favoriteSongs()`, the same source
/// `FavoritesManager` loads from, so the star state on a row and the contents
/// of this list can't disagree.
@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    @Published var loadError: String?

    func fetch(force: Bool = false) {
        guard !isLoading else { return }
        guard force || songs.isEmpty else { return }
        guard CredentialStore.isAuthenticated else {
            songs = []
            return
        }
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                songs = try await KaraokeAPIClient.favoriteSongs()
            } catch {
                loadError = "Check your connection and try again."
            }
        }
    }

    /// Drops a song the listener just un-starred from this screen, without
    /// waiting for a round trip that would make the row linger.
    func remove(songID: String) {
        songs.removeAll { $0.id == songID }
    }

    func reset() {
        songs = []
        loadError = nil
    }
}
