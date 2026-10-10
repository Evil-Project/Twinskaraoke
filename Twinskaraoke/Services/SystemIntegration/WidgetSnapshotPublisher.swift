import AppIntents
import Foundation
import WidgetKit
import SDWebImage
import UIKit

@MainActor
final class WidgetSnapshotPublisher {
    static let shared = WidgetSnapshotPublisher()
    private var observation: ObservationToken?
    private var progressObservation: ObservationToken?
    private var playbackAnchor: PlaybackWidgetSnapshot?
    private var lastProgressCheck = Date.distantPast
    private var previousPlayback: PlaybackWidgetSnapshot?
    private var previousLibrary: LibraryWidgetSnapshot?
    private var artworkTask: Task<Void, Never>?
    private var artworkGeneration = 0
    private let artworkWriter = WidgetArtworkWriter()
    private var lastArtworkKeys: Set<String> = []
    private var currentPlaylist: Playlist?
    private var currentPlaylistSongIDs: Set<String> = []
    /// Tests can supply a temporary destination when the simulator host is unsigned.
    var store = WidgetSnapshotStore() {
        didSet {
            previousPlayback = nil
            previousLibrary = nil
            playbackAnchor = nil
        }
    }
    private var catalogSuggestions: [WidgetPlaylist] = []
    private var catalogAccountID: String?
    private var suggestionsTask: Task<Void, Never>?
    private var resolvedPlaylistCovers: [String: [URL]] = [:]

    func refreshLibrarySuggestions() {
        guard suggestionsTask == nil else { return }
        suggestionsTask = Task {
            let playlists = await PlaylistIntentRepository.suggestions()
            catalogSuggestions = playlists.map(PlaylistIntentRepository.snapshot)
            catalogAccountID = AuthManager.persistedUserID
            suggestionsTask = nil
            publish()
            await resolveVisiblePlaylistCovers()
        }
    }

    private func coverURLs(for playlist: Playlist) -> [URL] {
        if playlist.isFavorites { return [] }
        if let media = playlist.media,
           let url = ArtworkURLBuilder.imageURL(cloudflareID: media.cloudflareId, path: media.absolutePath, variant: .card) {
            return [url]
        }
        return resolvedPlaylistCovers[playlist.id] ?? playlist.initialMosaicArtworkURLs
    }

    private func resolveVisiblePlaylistCovers() async {
        let candidates = Array(PinnedPlaylistsStore.shared.playlists.prefix(4))
            + Array(RecentlyPlayedStore.shared.playlists.prefix(4))
            + Array(SavedPlaylistsStore.shared.playlists.prefix(4))
        var seen = Set<String>()
        for playlist in candidates where seen.insert(playlist.id).inserted {
            guard !playlist.isFavorites, playlist.media == nil,
                  playlist.initialMosaicArtworkURLs.count < 4 else { continue }
            // Use the same playlist-detail source as PlaylistCoverLoader in the
            // app. The extension receives only the four cached image names.
            guard let data = try? await KaraokeAPIClient.playlistDetailData(id: playlist.id),
                  let detail = try? JSONDecoder().decode(Playlist.self, from: data) else { continue }
            let urls: [URL]
            if let media = detail.media,
               let cover = ArtworkURLBuilder.imageURL(cloudflareID: media.cloudflareId, path: media.absolutePath, variant: .card) {
                urls = [cover]
            } else {
                urls = detail.initialMosaicArtworkURLs
            }
            guard !urls.isEmpty else { continue }
            resolvedPlaylistCovers[playlist.id] = urls
            publish()
        }
    }

    func start() {
        guard observation == nil else { return }
        observation = observeContinuously({ [weak self] in
            _ = self?.snapshots()
        }, onChange: { [weak self] in self?.publish() })
        progressObservation = observeContinuously({ _ = AudioPlayerManager.shared.progress }, onChange: { [weak self] in
            self?.reconcilePlaybackPosition()
        })
        publish()
        refreshLibrarySuggestions()
    }

    private func reconcilePlaybackPosition() {
        guard Date().timeIntervalSince(lastProgressCheck) >= 1 else { return }
        lastProgressCheck = .now
        guard let playbackAnchor, !playbackAnchor.isRadio,
              abs(playbackAnchor.elapsed(at: .now) - AudioPlayerManager.shared.playbackTime) > 3 else { return }
        publish(forcePlayback: true)
    }

    func recordPlaylist(_ playlist: Playlist, songs: [Song]) {
        currentPlaylist = playlist
        currentPlaylistSongIDs = Set(songs.map(\.id))
        publish()
    }

    private func song(_ song: Song) -> WidgetSong {
        WidgetSong(id: song.id, title: song.title, artist: song.displayArtist,
                   originalArtists: song.originalArtists ?? [], coverArtists: song.coverArtists ?? [],
                   duration: song.duration,
                   artworkFilename: song.thumbnailURL.map { WidgetArtworkStore.filename(for: $0.absoluteString) })
    }
    private func playlist(_ playlist: Playlist) -> WidgetPlaylist {
        let covers = coverURLs(for: playlist)
        return WidgetPlaylist(id: playlist.id, name: playlist.name, songCount: playlist.songCount,
                       isPersonal: playlist.isPersonal || playlist.isFavorites,
                       artworkFilename: covers.first.map { WidgetArtworkStore.filename(for: $0.absoluteString) },
                       artworkFilenames: covers.map { WidgetArtworkStore.filename(for: $0.absoluteString) })
    }
    private func snapshots() -> (PlaybackWidgetSnapshot, LibraryWidgetSnapshot) {
        let player = AudioPlayerManager.shared
        let favorites = FavoritesManager.shared
        var playback = PlaybackWidgetSnapshot()
        playback.updatedAt = .distantPast // Exclude timestamps when comparing state.
        playback.song = player.currentSong.map(song)
        playback.isPlaying = player.isPlaying
        playback.isRadio = player.isRadioMode
        playback.isBuffering = player.isBuffering
        playback.hasPrevious = player.currentSong != nil && !player.isRadioMode && !player.queue.isEmpty
        let index = player.queue.firstIndex { $0.id == player.currentSong?.id }
        playback.hasNext = !player.isRadioMode && index.map { $0 + 1 < player.queue.count } == true
        playback.isFavorite = player.currentSong.map { favorites.isFavorite($0.id) } ?? false
        playback.playbackMode = player.karaokeMode ? "Instrumental" : "Original"
        playback.repeatMode = String(describing: player.repeatMode)
        playback.isShuffled = player.isShuffled
        if let index { playback.queue = player.queue.dropFirst(index + 1).prefix(4).map(song) }
        if let currentPlaylist, (favorites.isAvailable || (!currentPlaylist.isPersonal && !currentPlaylist.isFavorites)), player.currentSong.map({ currentPlaylistSongIDs.contains($0.id) }) == true, player.queue.allSatisfy({ currentPlaylistSongIDs.contains($0.id) }) {
            playback.playlistID = currentPlaylist.id
            playback.playlistName = currentPlaylist.name
        }
        var library = LibraryWidgetSnapshot()
        library.updatedAt = .distantPast
        library.accountAvailable = favorites.isAvailable
        let visible: (Playlist) -> Bool = { library.accountAvailable || (!$0.isPersonal && !$0.isFavorites) }
        library.recent = RecentlyPlayedStore.shared.playlists.filter(visible).prefix(12).map(playlist)
        library.pinned = PinnedPlaylistsStore.shared.playlists.filter(visible).map(playlist)
        library.saved = SavedPlaylistsStore.shared.playlists.filter(visible).prefix(20).map(playlist)
        library.personal = library.accountAvailable ? UserPlaylistsManager.shared.playlists.prefix(20).map { playlist($0.asPlaylist()) } : []
        library.favoriteCount = favorites.favoriteIDs.count
        library.downloadedCount = DownloadManager.shared.downloadedIDs.count
        library.catalogSuggestions = catalogSuggestions.filter { (library.accountAvailable && catalogAccountID == AuthManager.persistedUserID) || !$0.isPersonal }
        return (playback, library)
    }
    func publish(forcePlayback: Bool = false) {
        let (playback, library) = snapshots()
        if (previousLibrary?.accountAvailable ?? store.readLibrary().accountAvailable) && !library.accountAvailable {
            currentPlaylist = nil
            artworkGeneration += 1
            // The clear runs on the writer after any write already in flight
            // has finished, so a cover from the signed-out account cannot land
            // after it. The next caching pass waits for this task in turn.
            artworkTask?.cancel()
            let superseded = artworkTask
            let writer = artworkWriter
            artworkTask = Task {
                await superseded?.value
                await writer.clear()
            }
            lastArtworkKeys = []
            resolvedPlaylistCovers = [:]
        }
        do {
            if forcePlayback || playback != previousPlayback {
                var value = playback
                value.updatedAt = .now
                value.elapsedSeconds = AudioPlayerManager.shared.playbackTime
                value.durationSeconds = AudioPlayerManager.shared.playbackDuration
                try store.write(value)
                playbackAnchor = value
                previousPlayback = playback
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.nowPlaying)
            }
            if library != previousLibrary {
                var value = library
                value.updatedAt = .now
                try store.write(value)
                previousLibrary = library
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.recent)
                IOSAppShortcuts.updateAppShortcutParameters()
            }
        } catch {
            DebugLogger.log("Widget snapshot unavailable: \(error.localizedDescription)", category: .cache)
        }
        cacheArtwork()
    }
    private func cacheArtwork() {
        let accountAvailable = FavoritesManager.shared.isAvailable
        let playlists = RecentlyPlayedStore.shared.playlists + PinnedPlaylistsStore.shared.playlists + SavedPlaylistsStore.shared.playlists
        let player = AudioPlayerManager.shared
        let currentIndex = player.queue.firstIndex { $0.id == player.currentSong?.id }
        let upcomingArtwork = currentIndex.map { index in
            player.queue.dropFirst(index + 1).prefix(3).compactMap(\.thumbnailURL)
        } ?? []
        let urls = ([player.currentSong?.thumbnailURL].compactMap { $0 } + upcomingArtwork
                    + playlists.filter { accountAvailable || (!$0.isPersonal && !$0.isFavorites) }.prefix(32).flatMap(coverURLs))
        let keys = Set(urls.map(\.absoluteString))
        guard keys != lastArtworkKeys else { return }
        lastArtworkKeys = keys
        artworkTask?.cancel()
        let superseded = artworkTask
        artworkGeneration += 1
        let generation = artworkGeneration
        let writer = artworkWriter
        // Reading the app's image cache, re-encoding a square thumbnail and
        // pruning the shared folder all happen on the writer, off the main
        // actor. This runs at launch and on every song change — the moment
        // the player and its artwork are animating — and used to do all of
        // that, for up to forty covers, on the main thread.
        artworkTask = Task { [weak self] in
            await superseded?.value
            var changed = false
            for url in urls {
                guard !Task.isCancelled else { return }
                if await writer.cache(url) { changed = true }
            }
            guard changed, !Task.isCancelled, generation == self?.artworkGeneration else { return }
            for kind in [WidgetKinds.recent, WidgetKinds.nowPlaying] {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }
}

/// Serialises every write to the shared widget artwork folder off the main
/// actor. Being one actor is what orders a sign-out's clear after a write that
/// was already under way.
private actor WidgetArtworkWriter {
    /// Stores the widget copy of `url`, returning whether a new file landed.
    func cache(_ url: URL) async -> Bool {
        let artwork = WidgetArtworkStore()
        let filename = WidgetArtworkStore.filename(for: url.absoluteString)
        if let file = artwork.url(for: filename), FileManager.default.fileExists(atPath: file.path) {
            return false
        }
        // The app normally displays the card variant while the widget
        // snapshot names the thumbnail variant. Reuse whichever of the app's
        // existing variants is cached; constructing a URL here never sends a
        // new Cloudflare transformation request.
        let cachedURLs = [url] + [ArtworkImageVariant.card, .row, .hero]
            .compactMap { ArtworkURLBuilder.variantURL(from: url, variant: $0) }
        let cached = cachedURLs.lazy.compactMap { candidate in
            SDImageCache.shared.diskImageData(forKey: candidate.absoluteString)
                ?? SDImageCache.shared.imageFromMemoryCache(forKey: candidate.absoluteString)?
                .jpegData(compressionQuality: 0.9)
        }.first
        if let cached, (try? artwork.store(cached, key: url.absoluteString)) != nil {
            return true
        }
        // Fetch only the original delivery URL. Do not create a new
        // Cloudflare resize/format request for a widget.
        guard let original = WidgetArtworkStore.originalURL(for: url) else { return false }
        var request = URLRequest(url: original)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 8_000_000,
              // Checked after the request: a sign-out cancels this pass and
              // queues a clear, which may have run while this was suspended.
              !Task.isCancelled
        else { return false }
        return (try? artwork.store(data, key: url.absoluteString)) != nil
    }

    func clear() {
        try? WidgetArtworkStore().clear()
    }
}
