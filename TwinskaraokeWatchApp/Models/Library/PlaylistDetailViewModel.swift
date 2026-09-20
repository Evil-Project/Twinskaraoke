import Foundation
import Observation

@MainActor
@Observable
final class PlaylistDetailViewModel {
    var songs: [Song] = []
    var isLoading = false
    var loadError: String?
    let playlistID: String
    private let fallbackSongs: [Song]
    private var hasLoadedRemoteSongs = false

    init(playlistID: String, fallbackSongs: [Song] = []) {
        self.playlistID = playlistID
        self.fallbackSongs = fallbackSongs
        songs = fallbackSongs
    }

    func fetchSongs() {
        guard !isLoading, !hasLoadedRemoteSongs else { return }
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let loaded = try await KaraokeAPIClient.playlistSongs(id: playlistID)
                hasLoadedRemoteSongs = true
                if !loaded.isEmpty || fallbackSongs.isEmpty {
                    songs = loaded
                }
            } catch {
                if songs.isEmpty {
                    loadError = String(localized: "Check your connection and try again.")
                }
            }
        }
    }
}
