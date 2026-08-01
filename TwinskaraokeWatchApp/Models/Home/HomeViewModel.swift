import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var trending: [Song] = []
    @Published var isLoading = false

    func fetchTrending() {
        if AppRuntime.isUITestMode {
            applyUITestFixture()
            return
        }
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

    private func applyUITestFixture() {
        isLoading = false
        trending = [
            UITestFixtures.song(
                id: "watch-ui-song-1",
                title: "Wake Me Up Before You Go-Go",
                originalArtists: ["Wham!"],
                coverArtists: ["Neuro"],
                userUploaded: false
            ),
            UITestFixtures.song(
                id: "watch-ui-song-2",
                title: "Hero",
                originalArtists: ["Mili"],
                coverArtists: ["Neuro"],
                userUploaded: false
            ),
            UITestFixtures.song(
                id: "watch-ui-song-3",
                title: "Cure For Me",
                originalArtists: ["AURORA"],
                coverArtists: ["Neuro"],
                userUploaded: false
            ),
        ]
    }
}
