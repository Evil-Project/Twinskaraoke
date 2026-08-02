import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var trending: [Song] = []
    var latest: [Song] = []
    var isLoading = false
    var loadError: String?

    func fetch() {
        guard !isLoading, trending.isEmpty else { return }
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            async let trendingResult = KaraokeAPIClient.trendingSongs(take: 24)
            async let latestResult = KaraokeAPIClient.latestReleases(take: 24)
            do {
                trending = try await trendingResult
                latest = (try? await latestResult) ?? []
            } catch {
                loadError = "Check your connection and try again."
            }
        }
    }
}
