import Foundation
import Observation
@MainActor
@Observable
final class BrowseViewModel {
    private(set) var trending: [Song] = []
    private(set) var latest: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoaded = false
    private var generation = 0

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        generation &+= 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        defer {
            if generation == requestGeneration {
                isLoading = false
            }
        }
        async let trendingTask = KaraokeAPIClient.trendingSongs(days: 7, take: 24)
        async let latestTask = KaraokeAPIClient.latestReleases(pageSize: 48, take: 24)

        do {
            let songs = try await trendingTask
            guard generation == requestGeneration, !Task.isCancelled else { return }
            trending = songs
        } catch {
            noteFailure(error, generation: requestGeneration)
        }
        do {
            let songs = try await latestTask
            guard generation == requestGeneration, !Task.isCancelled else { return }
            latest = songs
        } catch {
            noteFailure(error, generation: requestGeneration)
        }

        if generation == requestGeneration {
            hasLoaded = !trending.isEmpty || !latest.isEmpty
        }
    }

    private func noteFailure(_ error: Error, generation requestGeneration: Int) {
        guard generation == requestGeneration, !(error is CancellationError), errorMessage == nil else { return }
        errorMessage = String(localized: "Couldn't load songs. Check your connection and try again.")
    }
}
