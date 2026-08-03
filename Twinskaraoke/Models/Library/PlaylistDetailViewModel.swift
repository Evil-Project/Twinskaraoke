import Foundation
import Observation

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

nonisolated struct PlaylistSearchRevealState: Equatable {
    static let revealThreshold: CGFloat = 88
    static let resetThreshold: CGFloat = 6
    static let hideThreshold: CGFloat = 18

    private(set) var isArmed = false

    mutating func update(
        pullDistance: CGFloat,
        isSearchVisible: Bool,
        isActivelyPulling: Bool
    ) -> Bool {
        if pullDistance <= Self.resetThreshold {
            isArmed = false
        }

        guard !isSearchVisible,
              isActivelyPulling,
              !isArmed,
              pullDistance >= Self.revealThreshold
        else {
            return false
        }

        isArmed = true
        return true
    }

    mutating func reset() {
        isArmed = false
    }

    static func shouldAutoHide(
        scrollOffset: CGFloat,
        isReady: Bool,
        isActivelyScrolling: Bool,
        isSearchModeActive: Bool
    ) -> Bool {
        isReady
            && isActivelyScrolling
            && !isSearchModeActive
            && scrollOffset >= hideThreshold
    }
}

@MainActor
@Observable
class PlaylistDetailViewModel {
    var songs: [Song]?
    var isLoading = false
    /// Presented as an alert. Kept apart from `emptyStateMessage`: a failed
    /// removal leaves a perfectly good song list on screen.
    var removeError: String?
    private(set) var hasAuthoritativeSongs = false
    private var loadFailed = false
    private var loadedID: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    var emptyStateMessage: String {
        if loadFailed {
            return "The playlist couldn't be loaded. Check your connection and try again."
        }
        return "Tap refresh to check for new songs."
    }

    /// Takes a song out of one of the user's own playlists, dropping the row
    /// straight away and putting it back if the server refuses. Keyed on song
    /// ID rather than a row offset because the visible list may be filtered by
    /// the search field while this runs.
    func removeSong(_ song: Song, from playlistID: String) {
        guard let index = songs?.firstIndex(where: { $0.id == song.id }) else { return }
        let previousSongs = songs
        songs?.remove(at: index)

        UserPlaylistsManager.shared.removeSong(song.id, fromPlaylist: playlistID) { [weak self] ok in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard ok else {
                    songs = previousSongs
                    AppHaptic.error.play()
                    removeError = String(
                        localized: "Couldn't remove \(song.title). Please try again."
                    )
                    return
                }
                AppHaptic.success.play()
                // A playlist can list the same song twice, and the server
                // decides whether it drops one entry or both — re-read rather
                // than trusting the local edit.
                reload(playlistID: playlistID)
            }
        }
    }

    func reload(playlistID: String, fallback: [Song]? = nil) {
        loadedID = nil
        loadFailed = false
        hasAuthoritativeSongs = false
        load(playlistID: playlistID, fallback: fallback)
    }

    func load(playlistID: String, fallback: [Song]?) {
        let alreadyLoaded = (loadedID == playlistID) && songs != nil && !isLoading
        if alreadyLoaded { return }
        if loadedID != playlistID {
            hasAuthoritativeSongs = false
        }
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
            hasAuthoritativeSongs = true
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
                        requestFailed: false,
                        isAuthoritative: false
                    )
                }

                let loadedSongs = try await remoteSongs
                guard !Task.isCancelled else { return }
                self?.applyLoadedSongs(
                    loadedSongs,
                    playlistID: playlistID,
                    requestFailed: false,
                    isAuthoritative: true
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
                    requestFailed: false,
                    isAuthoritative: true
                )
            } catch {
                guard !Task.isCancelled else { return }
                DebugLogger.log(
                    "Playlist \(playlistID) load failed: \(String(describing: error))",
                    category: .network
                )
                self?.applyLoadedSongs(
                    nil,
                    playlistID: playlistID,
                    requestFailed: true,
                    isAuthoritative: false
                )
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func applyLoadedSongs(
        _ list: [Song]?,
        playlistID: String,
        requestFailed: Bool,
        isAuthoritative: Bool
    ) {
        guard loadedID == playlistID else { return }
        if let list {
            songs = list
            if isAuthoritative {
                hasAuthoritativeSongs = true
                PlaylistSongCountStore.shared.recordResolvedCount(list.count, for: playlistID)
            }
        }
        loadFailed = requestFailed && (songs?.isEmpty ?? true)
        // A non-authoritative fallback apply means the remote fetch is still in
        // flight; keep isLoading true until the authoritative or failure apply.
        if isAuthoritative || requestFailed {
            isLoading = false
        }
    }
}
