import Foundation
import Observation

/// The signed-in listener's favorite songs.
///
/// Reads through `KaraokeAPIClient.favoriteSongs()`, the same source
/// `FavoritesManager` loads from, so the star state on a row and the contents
/// of this list can't disagree.
@MainActor
@Observable
final class FavoritesViewModel {
    var songs: [Song] = []
    var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    var loadError: String?
    /// Set when the phone says we are signed in but the token it holds has not
    /// reached this watch yet. Without it an empty list reads as "no favorites"
    /// when the truth is "could not ask".
    var needsPhoneSession = false

    func fetch(force: Bool = false) {
        guard !isLoading else { return }
        guard force || songs.isEmpty else { return }
        guard CredentialStore.isAuthenticated else {
            songs = []
            loadError = nil
            needsPhoneSession = true
            return
        }
        needsPhoneSession = false
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                songs = try await KaraokeAPIClient.favoriteSongs()
                needsPhoneSession = false
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
        needsPhoneSession = false
    }
}
