import Foundation
import Observation

@MainActor
@Observable
final class PlaylistDetailViewModel {
    var songs: [Song] = []
    var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    var loadError: String?
    let playlistID: String
    /// Songs the caller already had — personal playlists arrive from
    /// `/api/user/playlists` with their contents inline. Shown immediately so
    /// the screen is never blank while the network answers, and kept if the
    /// answer is empty or unavailable. The same authenticated detail loader
    /// as iPhone supplies full audio metadata once account sync completes.
    private let fallbackSongs: [Song]
    private let loadSongs: @Sendable (String) async throws -> [Song]
    private var hasLoadedRemoteSongs = false

    init(playlistID: String, fallbackSongs: [Song] = [],
         loadSongs: @escaping @Sendable (String) async throws -> [Song] = {
             try await KaraokeAPIClient.playlistSongs(id: $0)
         }) {
        self.loadSongs = loadSongs
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
                let loaded = try await loadSongs(playlistID)
                hasLoadedRemoteSongs = true
                if !loaded.isEmpty || fallbackSongs.isEmpty {
                    songs = loaded
                }
            } catch {
                // Only worth saying when there is nothing on screen to say it
                // over; a personal playlist showing its inline songs does not
                // need an error about the fetch that would have replaced them.
                if songs.isEmpty {
                    loadError = String(localized: "Check your connection and try again.")
                }
            }
        }
    }
}
