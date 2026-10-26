import Foundation

@MainActor
enum AppServices {
    private static var started = false
    private static let radioWidgets = RadioWidgetPublisher()

    static func start() {
        guard !started else { return }
        started = true
        SongArtworkFallback.shared.configure { id in
            guard let art = FallbackArtProvider.shared.art(for: id) else { return nil }
            return SongArtworkFallback.Artwork(url: art.url, artistName: art.artistName)
        }
        let auth = AuthManager.shared
        auth.onSwitchAccount = { PinnedPlaylistsStore.shared.switchAccount(to: $0) }
        auth.onClearAccountState = {
            FavoritesManager.shared.clear()
            UserPlaylistsManager.shared.clear()
            RecentSearchesStore.shared.clear()
        }
        auth.onSignedIn = {
            FavoritesManager.shared.reload()
            UserPlaylistsManager.shared.fetchPlaylists(force: true)
        }
        if !auth.isRestoringSession {
            PinnedPlaylistsStore.shared.switchAccount(to: auth.isLoggedIn ? auth.currentUserId : nil)
        }
        CacheManager.onImageCacheCleared = { FallbackArtProvider.shared.resetBindings() }
        DownloadManager.onQueueFinished = { completed, failed, cancelled in
            if completed > 1, failed == 0, cancelled == 0 { AppHaptic.celebrate.play() }
            DownloadNotifications.shared.downloadsFinished(completed: completed, failed: failed)
        }
        PlaylistPlayback.onPlaylistPlayed = { WidgetSnapshotPublisher.shared.recordPlaylist($0, songs: $1) }
        let player = AudioPlayerManager.shared
        player.stopRadioMetadata = { RadioController.shared.stop() }
        let radio = RadioController.shared
        radio.isRadioPlaying = { AudioPlayerManager.shared.isRadioMode }
        radio.playStream = { AudioPlayerManager.shared.playRadio(streamURL: $0, song: $1, artworkURL: $2) }
        radio.updateMetadata = { AudioPlayerManager.shared.updateRadioMetadata(song: $0, artworkURL: $1) }
        radio.metadataReceived = { radioWidgets.publish($0, fetchedAt: $1) }
        // Set the route before activation may apply a saved watch snapshot.
        player.companionRouter = WatchSessionPublisher.shared
        WatchSessionPublisher.shared.activate()
    }
}
