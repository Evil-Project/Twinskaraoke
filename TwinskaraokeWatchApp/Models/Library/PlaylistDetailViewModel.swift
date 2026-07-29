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
    /// Songs the caller already had — personal playlists arrive from
    /// `/api/user/playlists` with their contents inline. Shown immediately so
    /// the screen is never blank while the network answers, and kept if the
    /// answer is an empty list, which is what the curated endpoint says about
    /// a playlist ID it does not know.
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
                // Only worth saying when there is nothing on screen to say it
                // over; a personal playlist showing its inline songs does not
                // need an error about the fetch that would have replaced them.
                if songs.isEmpty {
                    loadError = "Check your connection and try again."
                }
            }
        }
    }
}
