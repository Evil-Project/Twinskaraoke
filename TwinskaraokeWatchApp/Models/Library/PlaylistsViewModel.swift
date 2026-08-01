import Combine
import Foundation

@MainActor
final class PlaylistsViewModel: ObservableObject {
    typealias Loader = @Sendable () async throws -> [Playlist]

    @Published var playlists: [Playlist] = []
    @Published var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private let loader: Loader

    init(
        loader: @escaping Loader = {
            try await KaraokeAPIClient.playlists(
                startIndex: 0,
                pageSize: 15,
                isSetlist: true,
                sortDescending: false
            )
        }
    ) {
        self.loader = loader
    }

    deinit {
        loadTask?.cancel()
    }

    func fetchMusic(force: Bool = false) {
        guard force || (!isLoading && playlists.isEmpty) else { return }

        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        isLoading = true
        loadErrorMessage = nil
        let loader = loader
        loadTask = Task { @MainActor [weak self, loader] in
            do {
                let playlists = try await loader()
                guard let self,
                      generation == self.loadGeneration,
                      !Task.isCancelled
                else { return }
                self.playlists = playlists
                self.loadErrorMessage = nil
            } catch {
                guard let self,
                      generation == self.loadGeneration,
                      !Task.isCancelled
                else { return }
                self.playlists = []
                self.loadErrorMessage =
                    "Playlists are temporarily unavailable. Check your connection and try again."
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
