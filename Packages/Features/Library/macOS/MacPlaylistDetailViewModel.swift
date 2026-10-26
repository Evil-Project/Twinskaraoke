import Foundation
import Observation

@MainActor
@Observable
final class MacPlaylistDetailViewModel {
    private(set) var songs: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var loadedID: String?
    private var generation = 0

    func load(playlistID: String) async {
        guard loadedID != playlistID else { return }
        generation &+= 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        songs = []
        defer {
            if generation == requestGeneration { isLoading = false }
        }
        do {
            let loaded = try await KaraokeAPIClient.playlistSongs(id: playlistID)
            guard generation == requestGeneration, !Task.isCancelled else { return }
            songs = loaded
            loadedID = playlistID
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "Couldn't load this playlist.")
        }
    }
}
