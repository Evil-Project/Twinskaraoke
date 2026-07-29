import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var trending: [Song] = []
    @Published var latest: [Song] = []
    @Published var isLoading = false
    @Published var loadError: String?

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
