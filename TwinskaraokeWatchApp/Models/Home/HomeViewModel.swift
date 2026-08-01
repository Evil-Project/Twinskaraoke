import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    typealias Loader = @Sendable () async throws -> [Song]

    @Published var trending: [Song] = []
    @Published var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private let loader: Loader

    init(
        loader: @escaping Loader = {
            try await KaraokeAPIClient.trendingSongs(take: 10)
        }
    ) {
        self.loader = loader
    }

    deinit {
        loadTask?.cancel()
    }

    func fetchTrending(force: Bool = false) {
        if AppRuntime.isUITestMode {
            applyUITestFixture()
            return
        }
        guard force || (!isLoading && trending.isEmpty) else { return }

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
                self.trending = songs
                self.loadErrorMessage = nil
            } catch {
                guard let self,
                      generation == self.loadGeneration,
                      !Task.isCancelled
                else { return }
                self.trending = []
                self.loadErrorMessage =
                    "Trending is temporarily unavailable. Check your connection and try again."
            }
            guard let self,
                  generation == self.loadGeneration,
                  !Task.isCancelled
            else { return }
            self.isLoading = false
            self.loadTask = nil
        }
    }

    private func applyUITestFixture() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        loadErrorMessage = nil
        trending = [
            UITestFixtures.song(
                id: "watch-ui-song-1",
                title: "Wake Me Up Before You Go-Go",
                originalArtists: ["Wham!"],
                coverArtists: ["Neuro"],
                userUploaded: false
            ),
            UITestFixtures.song(
                id: "watch-ui-song-2",
                title: "Hero",
                originalArtists: ["Mili"],
                coverArtists: ["Neuro"],
                userUploaded: false
            ),
            UITestFixtures.song(
                id: "watch-ui-song-3",
                title: "Cure For Me",
                originalArtists: ["AURORA"],
                coverArtists: ["Neuro"],
                userUploaded: false
            ),
        ]
    }
}
