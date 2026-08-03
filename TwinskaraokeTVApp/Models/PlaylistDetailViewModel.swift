import Foundation
import Observation

@MainActor
@Observable
final class PlaylistDetailViewModel {
    var songs: [Song] = []
    var isLoading = false
    var loadError: String?
    /// Surfaced as an alert, separate from `loadError`: a failed removal leaves
    /// a perfectly good song list on screen and mustn't replace it with a
    /// full-screen error state.
    var actionError: String?
    let playlistID: String

    init(playlistID: String) {
        self.playlistID = playlistID
    }

    func fetchSongs() {
        guard !isLoading, songs.isEmpty else { return }
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                songs = try await KaraokeAPIClient.playlistSongs(id: playlistID)
            } catch {
                loadError = "Check your connection and try again."
            }
        }
    }

    /// Removes the song at `index`, taking it off the list immediately and
    /// putting it back if the server refuses.
    func removeSong(at index: Int) {
        guard songs.indices.contains(index) else { return }
        let song = songs[index]
        let previousSongs = songs
        songs.remove(at: index)

        Task { [weak self] in
            guard let self else { return }
            let removed = await TVUserPlaylistsManager.shared.removeSong(
                song.id,
                from: playlistID
            )
            guard removed else {
                songs = previousSongs
                actionError = "Couldn’t remove “\(song.title)”. Try again."
                return
            }
            // A playlist may legitimately list the same song twice, and the
            // server decides whether it drops one entry or both — so take its
            // answer rather than trusting the local edit.
            if let reconciled = try? await KaraokeAPIClient.playlistSongs(id: playlistID) {
                songs = reconciled
            }
        }
    }
}
