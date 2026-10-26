import Foundation
import Observation

@MainActor
@Observable
final class MacFavoritesViewModel {
    private(set) var songs: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var generation = 0

    func reload() async {
        generation &+= 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        defer {
            if generation == requestGeneration { isLoading = false }
        }
        do {
            let loaded = try await KaraokeAPIClient.favoriteSongs()
            guard generation == requestGeneration, !Task.isCancelled else { return }
            songs = loaded
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "Couldn't load your favourites.")
        }
    }
}
