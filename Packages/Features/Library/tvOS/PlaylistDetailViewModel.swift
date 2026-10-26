import Foundation
import Observation

@MainActor
@Observable
final class PlaylistDetailViewModel {
    var songs: [Song] = []
    var isLoading = false
    var loadError: String?
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
                loadError = String(localized: "Check your connection and try again.")
            }
        }
    }
    func removeSong(at index: Int) {
        guard songs.indices.contains(index) else { return }
        let song = songs[index]
        songs.remove(at: index)

        Task { [weak self] in
            guard let self else { return }
            let removed = await TVUserPlaylistsManager.shared.removeSong(
                song.id,
                from: playlistID
            )
            guard removed else {
                songs.insert(song, at: min(index, songs.count))
                actionError = String(localized: "Couldn’t remove “\(song.title)”. Try again.")
                return
            }
            if let reconciled = try? await KaraokeAPIClient.playlistSongs(id: playlistID) {
                songs = reconciled
            }
        }
    }
}
