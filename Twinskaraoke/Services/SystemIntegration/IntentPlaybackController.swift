import Foundation
import WidgetKit

@MainActor
enum IntentPlaybackController {
    static func perform(_ action: PlaybackAction, playlistID: String? = nil, shuffle: Bool = false, repeatMode: IntentRepeatMode = .off) async throws {
        WidgetSnapshotPublisher.shared.start()
        let player = AudioPlayerManager.shared
        switch action {
        case .toggle:
            guard player.togglePlayPause() else { throw SystemIntentError.nothingLoaded }
        case .next:
            guard !player.isRadioMode, let song = player.currentSong,
                  let index = player.queue.firstIndex(where: { $0.id == song.id }),
                  index + 1 < player.queue.count else { throw SystemIntentError.noNext }
            player.skipToNext()
        case .previous:
            guard !player.isRadioMode, player.currentSong != nil, !player.queue.isEmpty else { throw SystemIntentError.noPrevious }
            player.playPrevious()
        case .radio:
            let radio = RadioController.shared
            await radio.refresh()
            guard radio.refreshErrorMessage == nil, let station = radio.nowPlaying?.station,
                  let url = URL(string: station.listenUrl), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else { throw SystemIntentError.stationUnavailable }
            radio.playLiveStream()
            if player.isRadioMode && !player.isPlaying && !player.isBuffering {
                guard player.togglePlayPause() else { throw SystemIntentError.stationUnavailable }
            }
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.radio)
        case .favorites:
            try await playFavorites(shuffle: shuffle)
        case .downloads:
            let songs = DownloadManager.shared.downloadedSongs().filter { DownloadManager.shared.playableURL(for: $0) != nil }
            guard !songs.isEmpty else { throw SystemIntentError.emptyCollection }
            if shuffle { player.playShuffled(from: songs) }
            else { player.playInOrder(song: songs[0], context: songs) }
        case .playlist:
            guard let playlistID else { throw SystemIntentError.emptyCollection }
            if playlistID == "__favorites__" { try await playFavorites(shuffle: shuffle); break }
            if playlistID == "__downloads__" { try await perform(.downloads, shuffle: shuffle, repeatMode: repeatMode); break }
            if playlistID == "__radio__" { try await perform(.radio); break }
            let snapshot = WidgetSnapshotStore().readLibrary().suggestions.first { $0.id == playlistID }
            if snapshot?.isPersonal == true && !CredentialStore.isAuthenticated { throw SystemIntentError.signIn }
            let detail = try await KaraokeAPIClient.playlistDetail(id: playlistID)
            let songs = try await KaraokeAPIClient.playlistSongs(id: playlistID)
            guard let first = songs.first else { throw SystemIntentError.emptyCollection }
            let playlist = Playlist(id: detail.id, name: detail.name, songCount: songs.count, mosaicMedia: nil, songListDTOs: nil, isPersonal: snapshot?.isPersonal ?? false)
            if shuffle { PlaylistPlayback.playShuffled(from: playlist, songs: songs) }
            else { PlaylistPlayback.playInOrder(first, from: playlist, context: songs) }
        }
        if [.playlist, .favorites, .downloads].contains(action) {
            player.repeatMode = switch repeatMode { case .off: .off; case .all: .all; case .one: .one }
        }
        // AudioPlaybackIntent may be cancelled by Shortcuts as soon as the
        // player takes over audio. Return after the queue is installed; waiting
        // for an asynchronous buffering transition made successful plays look
        // like cancelled actions and prevented the next Shortcut step.
        WidgetSnapshotPublisher.shared.publish()
    }
    static func playFavorites(shuffle: Bool) async throws {
        guard CredentialStore.isAuthenticated else { throw SystemIntentError.signIn }
        let songs = try await KaraokeAPIClient.favoriteSongs()
        guard CredentialStore.isAuthenticated else { throw SystemIntentError.signIn }
        guard let first = songs.first else { throw SystemIntentError.emptyCollection }
        let playlist = Playlist(id: Playlist.favoritesID, name: String(localized: "Favorites"), songCount: songs.count, mosaicMedia: nil, songListDTOs: nil, isPersonal: true)
        if shuffle { PlaylistPlayback.playShuffled(from: playlist, songs: songs) }
        else { PlaylistPlayback.playInOrder(first, from: playlist, context: songs) }
    }
    static func favoriteCurrentSong() async throws {
        guard CredentialStore.isAuthenticated else { throw SystemIntentError.signIn }
        guard let song = AudioPlayerManager.shared.currentSong, !AudioPlayerManager.shared.isRadioMode else { throw SystemIntentError.nothingLoaded }
        // Resolve authoritative membership first because the server's PUT toggles membership.
        let account = AuthManager.persistedUserID
        let favorites = try await KaraokeAPIClient.favoriteSongs()
        guard CredentialStore.isAuthenticated, AuthManager.persistedUserID == account else { throw SystemIntentError.signIn }
        if favorites.contains(where: { $0.id == song.id }) {
            FavoritesManager.shared.reload()
            return
        }
        // A stale optimistic local flag must not turn the server's toggle into
        // a silent no-op. Refresh and ask for a retry rather than report success.
        if FavoritesManager.shared.isFavorite(song.id) {
            FavoritesManager.shared.reload()
            throw SystemIntentError.favoriteFailed
        }
        guard await FavoritesManager.shared.add(songID: song.id) else { throw SystemIntentError.favoriteFailed }
        WidgetSnapshotPublisher.shared.publish()
    }
    static func changeSetting(_ setting: PlaybackSetting) throws -> String {
        WidgetSnapshotPublisher.shared.start()
        let player = AudioPlayerManager.shared
        guard player.currentSong != nil, !player.isRadioMode else { throw SystemIntentError.nothingLoaded }
        switch setting {
        case .toggleRepeat: player.toggleRepeat()
        case .toggleShuffle: player.toggleShuffle()
        }
        WidgetSnapshotPublisher.shared.publish()
        switch setting {
        case .toggleShuffle:
            return player.isShuffled ? String(localized: "Shuffle is on.") : String(localized: "Shuffle is off.")
        case .toggleRepeat:
            switch player.repeatMode {
            case .off: return String(localized: "Don't Repeat.")
            case .all: return String(localized: "Repeat this song.")
            case .one: return String(localized: "Repeat this song once.")
            }
        }
    }
    static func startSleepTimer(_ duration: SleepTimerDuration) throws {
        let player = AudioPlayerManager.shared
        guard player.currentSong != nil else { throw SystemIntentError.nothingLoaded }
        if duration == .endOfSong {
            guard !player.isRadioMode else { throw SystemIntentError.liveTimer }
            player.startSleepTimerAtEndOfSong()
        } else { player.setSleepTimer(minutes: duration.minutes) }
    }
}
