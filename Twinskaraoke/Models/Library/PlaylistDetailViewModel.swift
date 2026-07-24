import Combine
import Foundation

nonisolated enum PlaylistSongSearch {
    static func filter(_ songs: [Song], matching searchText: String) -> [Song] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return songs }

        return songs.filter { song in
            song.title.localizedCaseInsensitiveContains(query)
                || song.displayArtist.localizedCaseInsensitiveContains(query)
                || song.displayTitle.localizedCaseInsensitiveContains(query)
        }
    }
}

@MainActor
class PlaylistDetailViewModel: ObservableObject {
    @Published var songs: [Song]?
    @Published var isLoading = false
    @Published private var loadFailed = false
    private var loadedID: String?
    private var loadTask: Task<Void, Never>?
    var emptyStateMessage: String {
        if loadFailed {
            return "The playlist couldn't be loaded. Check your connection and try again."
        }
        return "Tap refresh to check for new songs."
    }

    func reload(playlistID: String, fallback: [Song]? = nil) {
        loadedID = nil
        loadFailed = false
        load(playlistID: playlistID, fallback: fallback)
    }

    func load(playlistID: String, fallback: [Song]?) {
        let alreadyLoaded = (loadedID == playlistID) && songs != nil && !isLoading
        if alreadyLoaded { return }
        loadedID = playlistID
        loadTask?.cancel()
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
        loadTask = Task { [weak self] in
            do {
                async let remoteSongs = KaraokeAPIClient.playlistSongs(id: playlistID)

                if let fallback, !fallback.isEmpty {
                    let fallbackWithDurations = await UploadedSongDurationResolver.shared
                        .fillingMissingDurations(in: fallback)
                    guard !Task.isCancelled else { return }
                    self?.applyLoadedSongs(
                        fallbackWithDurations,
                        playlistID: playlistID,
                        requestFailed: false
                    )
                }

                let loadedSongs = try await remoteSongs
                guard !Task.isCancelled else { return }
                self?.applyLoadedSongs(
                    loadedSongs,
                    playlistID: playlistID,
                    requestFailed: false
                )

                let songsWithDurations = await UploadedSongDurationResolver.shared
                    .fillingMissingDurations(in: loadedSongs)
                guard !Task.isCancelled else { return }
                DebugLogger.log(
                    "Playlist duration hydration \(playlistID): resolved="
                        + "\(songsWithDurations.filter { $0.duration > 0 }.count), "
                        + "missing=\(songsWithDurations.filter { $0.duration <= 0 }.count)",
                    category: .cache
                )
                self?.applyLoadedSongs(
                    songsWithDurations,
                    playlistID: playlistID,
                    requestFailed: false
                )
            } catch {
                guard !Task.isCancelled else { return }
                DebugLogger.log(
                    "Playlist \(playlistID) load failed: \(String(describing: error))",
                    category: .network
                )
                self?.applyLoadedSongs(nil, playlistID: playlistID, requestFailed: true)
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func applyLoadedSongs(_ list: [Song]?, playlistID: String, requestFailed: Bool) {
        guard loadedID == playlistID else { return }
        if let list {
            songs = list
        }
        loadFailed = requestFailed && (songs?.isEmpty ?? true)
        isLoading = false
    }
}
