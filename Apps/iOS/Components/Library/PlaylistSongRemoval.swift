import SwiftUI

/// Carries "this row is inside a playlist you can edit" down to the shared song
/// context menu.
///
/// Passed through the environment rather than as a `SongRow` parameter: `SongRow`
/// and `SongActionsMenuItems` are used on a dozen screens that have no playlist
/// to remove from, and only `PlaylistDetailView` can supply one. Where nothing
/// injects it the value stays nil and the menu item is absent.
struct PlaylistSongRemovalContext {
    let playlistID: String
    let playlistName: String
    let remove: (Song) -> Void
}

private struct PlaylistSongRemovalKey: EnvironmentKey {
    // Computed rather than a stored `static let` so the non-Sendable context
    // type doesn't become shared mutable state under strict concurrency.
    static var defaultValue: PlaylistSongRemovalContext? { nil }
}

extension EnvironmentValues {
    /// Non-nil only inside a playlist the signed-in user owns and may edit.
    var playlistSongRemoval: PlaylistSongRemovalContext? {
        get { self[PlaylistSongRemovalKey.self] }
        set { self[PlaylistSongRemovalKey.self] = newValue }
    }
}
