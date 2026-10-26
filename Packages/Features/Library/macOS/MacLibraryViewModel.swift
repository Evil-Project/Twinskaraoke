import Foundation
import Observation

@MainActor
@Observable
final class MacLibraryViewModel {
    private(set) var playlists: [Playlist] = []
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
            if generation == requestGeneration { isLoading = false }
        }
        do {
            let loaded = try await KaraokeAPIClient.publicPlaylists(
                startIndex: 0,
                pageSize: 100
            )
            guard generation == requestGeneration, !Task.isCancelled else { return }
            playlists = loaded
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "Couldn't load the library.")
        }
    }
}
