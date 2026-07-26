import Combine
import Foundation

@MainActor
final class SongsViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    @Published var loadError: String?

    func fetchSongs() {
        guard !isLoading, songs.isEmpty else { return }
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let songs = try await KaraokeAPIClient.trendingSongs(take: 20)
                self.songs = songs
            } catch {
                loadError = "Check your connection and try again."
            }
        }
    }
}
