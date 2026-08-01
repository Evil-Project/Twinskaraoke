import Foundation
import Observation

@MainActor
@Observable
final class PlaylistDetailViewModel {
    var songs: [Song] = []
    var isLoading = false
    var loadError: String?
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
}
