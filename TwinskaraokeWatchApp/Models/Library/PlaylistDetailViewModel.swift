import Combine
import Foundation

@MainActor
final class PlaylistDetailViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    @Published var loadError: String?
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
