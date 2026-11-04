import Foundation

/// Keeps recently played history tied to explicit playback from a playlist,
/// and tells the player which playlist the queue came from for play counts.
@MainActor
enum PlaylistPlayback {
    static func play(_ song: Song, from playlist: Playlist, context: [Song]) {
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.play(song: song, context: context, playlistID: playlist.id)
        WidgetSnapshotPublisher.shared.recordPlaylist(playlist, songs: context)
    }

    static func playInOrder(_ song: Song, from playlist: Playlist, context: [Song]) {
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.playInOrder(song: song, context: context, playlistID: playlist.id)
        WidgetSnapshotPublisher.shared.recordPlaylist(playlist, songs: context)
    }

    static func playShuffled(from playlist: Playlist, songs: [Song]) {
        guard !songs.isEmpty else { return }
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.playShuffled(from: songs, playlistID: playlist.id)
        WidgetSnapshotPublisher.shared.recordPlaylist(playlist, songs: songs)
    }
}
