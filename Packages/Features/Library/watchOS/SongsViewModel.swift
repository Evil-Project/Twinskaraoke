import Foundation
import Observation

@MainActor
@Observable
final class SongsViewModel {
    var songs: [Song] = []
    var isLoading = false
    var loadError: String?

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
                loadError = String(localized: "Check your connection and try again.")
            }
        }
    }
}
