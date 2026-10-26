import Foundation
@MainActor
enum PlaylistPlayback {
    static var onPlaylistPlayed: (Playlist, [Song]) -> Void = { _, _ in }
    static func play(_ song: Song, from playlist: Playlist, context: [Song]) {
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.play(song: song, context: context)
        onPlaylistPlayed(playlist, context)
    }

    static func playInOrder(_ song: Song, from playlist: Playlist, context: [Song]) {
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.playInOrder(song: song, context: context)
        onPlaylistPlayed(playlist, context)
    }

    static func playShuffled(from playlist: Playlist, songs: [Song]) {
        guard !songs.isEmpty else { return }
        RecentlyPlayedStore.shared.record(playlist)
        AudioPlayerManager.shared.playShuffled(from: songs)
        onPlaylistPlayed(playlist, songs)
    }
}
