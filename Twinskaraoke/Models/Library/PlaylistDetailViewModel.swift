import Combine
import Foundation

@MainActor
final class PlaylistDetailViewModel: ObservableObject {
    typealias PlaylistSongsLoader = @Sendable (_ playlistID: String) async throws -> [Song]

    @Published var songs: [Song]?
    @Published var isLoading = false
    @Published private var loadFailed = false
    private var loadedID: String?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private let playlistSongsLoader: PlaylistSongsLoader

    init(
        playlistSongsLoader: @escaping PlaylistSongsLoader = { playlistID in
            try await KaraokeAPIClient.playlistSongs(id: playlistID)
        }
    ) {
        self.playlistSongsLoader = playlistSongsLoader
    }

    var emptyStateMessage: String {
        if loadFailed {
            return "The playlist couldn't be loaded. Check your connection and try again."
        }
        return "Pull down or tap refresh to check for new songs."
    }

    func reload(playlistID: String, fallback: [Song]? = nil) {
        loadedID = nil
        loadFailed = false
        load(playlistID: playlistID, fallback: fallback)
    }

    func reloadForSessionChange(playlistID: String) {
        invalidateCurrentLoad()
        loadedID = nil
        songs = []
        loadFailed = false
        load(playlistID: playlistID, fallback: nil)
    }

    func load(playlistID: String, fallback: [Song]?) {
        let alreadyLoaded = (loadedID == playlistID) && songs != nil && !isLoading
        if alreadyLoaded { return }
        invalidateCurrentLoad()
        loadedID = playlistID
        if songs?.isEmpty ?? true, let fallback, !fallback.isEmpty {
            songs = fallback
        }
        if AppRuntime.isUITestMode,
           let fallback, !fallback.isEmpty
        {
            loadTask = nil
            songs = fallback
            isLoading = false
            loadFailed = false
            return
        }
        isLoading = true
        let requestGeneration = loadGeneration
        let playlistSongsLoader = playlistSongsLoader
        loadTask = Task { @MainActor [weak self, playlistSongsLoader] in
            do {
                let loadedSongs = try await playlistSongsLoader(playlistID)
                guard !Task.isCancelled else { return }
                self?.applyLoadedSongs(
                    loadedSongs,
                    playlistID: playlistID,
                    requestGeneration: requestGeneration,
                    requestFailed: false
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyLoadedSongs(
                    nil,
                    playlistID: playlistID,
                    requestGeneration: requestGeneration,
                    requestFailed: true
                )
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func invalidateCurrentLoad() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func applyLoadedSongs(
        _ list: [Song]?,
        playlistID: String,
        requestGeneration: UInt64,
        requestFailed: Bool
    ) {
        guard requestGeneration == loadGeneration,
              loadedID == playlistID,
              !Task.isCancelled
        else { return }
        if let list {
            songs = list
        }
        loadFailed = requestFailed && (songs?.isEmpty ?? true)
        isLoading = false
        loadTask = nil
    }
}
