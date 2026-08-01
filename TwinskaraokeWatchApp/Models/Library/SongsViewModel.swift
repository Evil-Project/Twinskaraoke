import Combine
import Foundation

@MainActor
final class SongsViewModel: ObservableObject {
    typealias Loader = @Sendable () async throws -> [Song]

    @Published var songs: [Song] = []
    @Published var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private let loader: Loader

    init(
        loader: @escaping Loader = {
            try await KaraokeAPIClient.trendingSongs(take: 20)
        }
    ) {
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
        loadTask = Task { @MainActor [weak self, loader] in
            do {
                let songs = try await loader()
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
                    "Songs are temporarily unavailable. Check your connection and try again."
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
