import Combine
import Foundation

@MainActor
final class PlaylistDetailViewModel: ObservableObject {
    typealias Loader = @Sendable (_ playlistID: String) async throws -> [Song]

    @Published var songs: [Song] = []
    @Published var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    let playlistID: String
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private let loader: Loader

    init(
        playlistID: String,
        loader: @escaping Loader = { playlistID in
            try await KaraokeAPIClient.playlistSongs(id: playlistID)
        }
    ) {
        self.playlistID = playlistID
        self.loader = loader
    }

    deinit {
        loadTask?.cancel()
    }

    func fetchSongs(force: Bool = false) {
        guard force || (!isLoading && songs.isEmpty) else { return }

        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        isLoading = true
        loadErrorMessage = nil
        let loader = loader
        let playlistID = playlistID
        loadTask = Task { @MainActor [weak self, loader] in
            do {
                let songs = try await loader(playlistID)
                guard let self,
                      generation == self.loadGeneration,
                      !Task.isCancelled
                else { return }
                self.songs = songs
                self.loadErrorMessage = nil
            } catch {
                guard let self,
                      generation == self.loadGeneration,
                      !Task.isCancelled
                else { return }
                self.songs = []
                self.loadErrorMessage =
                    "This playlist is temporarily unavailable. Check your connection and try again."
            }
            guard let self,
                  generation == self.loadGeneration,
                  !Task.isCancelled
            else { return }
            self.isLoading = false
            self.loadTask = nil
        }
    }
}
