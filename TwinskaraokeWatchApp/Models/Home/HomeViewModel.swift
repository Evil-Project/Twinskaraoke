import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var trending: [Song] = []
    var isLoading = false

    func fetchTrending() {
        guard !isLoading, trending.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let songs = try await KaraokeAPIClient.trendingSongs(take: 10)
                trending = songs
            } catch {
                trending = []
            }
        }
    }
}
