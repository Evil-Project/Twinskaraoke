import Foundation
import Observation

/// Backs the Home screen: a trending shelf and a latest-releases shelf.
@MainActor
@Observable
final class BrowseViewModel {
    private(set) var trending: [Song] = []
    private(set) var latest: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Kick both off together, then unwrap each separately: one shelf
        // failing shouldn't blank the other.
        async let trendingTask = KaraokeAPIClient.trendingSongs(days: 7, take: 24)
        async let latestTask = KaraokeAPIClient.latestReleases(pageSize: 48, take: 24)

        do {
            trending = try await trendingTask
        } catch {
            noteFailure(error)
        }
        do {
            latest = try await latestTask
        } catch {
            noteFailure(error)
        }

        hasLoaded = !trending.isEmpty || !latest.isEmpty
    }

    private func noteFailure(_ error: Error) {
        guard !(error is CancellationError), errorMessage == nil else { return }
        errorMessage = "Couldn't load songs. Check your connection and try again."
    }
}
