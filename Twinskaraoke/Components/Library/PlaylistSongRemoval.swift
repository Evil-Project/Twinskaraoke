import SwiftUI
struct PlaylistSongRemovalContext {
    let playlistID: String
    let playlistName: String
    let remove: (Song) -> Void
}

private struct PlaylistSongRemovalKey: EnvironmentKey {
    static var defaultValue: PlaylistSongRemovalContext? { nil }
}

extension EnvironmentValues {
    var playlistSongRemoval: PlaylistSongRemovalContext? {
        get { self[PlaylistSongRemovalKey.self] }
        set { self[PlaylistSongRemovalKey.self] = newValue }
    }
}
