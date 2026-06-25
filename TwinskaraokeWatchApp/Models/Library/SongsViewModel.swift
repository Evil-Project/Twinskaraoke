import Combine
import Foundation

@MainActor
final class SongsViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading = false

    func fetchSongs() {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let songs = try await KaraokeAPIClient.trendingSongs(take: 20)
                self.songs = songs
            } catch {
                songs = []
            }
        }
    }
}
