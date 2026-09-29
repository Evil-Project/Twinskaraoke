import Foundation

/// Keeps recently played history tied to explicit playback from a playlist.
@MainActor
enum PlaylistPlayback {
    static func play(_ song: Song, from playlist: Playlist, context: [Song]) {
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.play(song: song, context: context)
        WidgetSnapshotPublisher.shared.recordPlaylist(playlist, songs: context)
    }

    static func playInOrder(_ song: Song, from playlist: Playlist, context: [Song]) {
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.playInOrder(song: song, context: context)
        WidgetSnapshotPublisher.shared.recordPlaylist(playlist, songs: context)
    }

    static func playShuffled(from playlist: Playlist, songs: [Song]) {
        guard !songs.isEmpty else { return }
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.playShuffled(from: songs)
        WidgetSnapshotPublisher.shared.recordPlaylist(playlist, songs: songs)
    }
}
