import SwiftUI

/// Carries "this row is inside a playlist you can edit" down to the shared song
/// context menu.
///
/// Passed through the environment rather than as a `SongRow` parameter: `SongRow`
/// and `SongActionsMenuItems` are used on a dozen screens that have no playlist
/// to remove from, and only `PlaylistDetailView` can supply one. Where nothing
/// injects it the value stays nil and the menu item is absent.
///
/// The menu only asks: `requestRemoval` puts up the screen's confirmation,
/// and the song goes once that is confirmed.
struct PlaylistSongRemovalContext {
    let playlistID: String
    let playlistName: String
    let requestRemoval: (Song) -> Void
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

/// The song a playlist screen asks about before removing it.
///
/// Held by the screen, not the row: the context menu that asks is gone by the
/// time the confirmation shows, and a dialog attached inside it never appears.
struct PendingPlaylistSongRemoval {
    private(set) var song: Song?

    var isPresented: Bool {
        get { song != nil }
        set { if !newValue { song = nil } }
    }

    mutating func request(_ song: Song) {
        self.song = song
    }
}

extension View {
    /// The confirmation Add to Playlist shows before it removes a song, with
    /// the same strings. Opening it ticks (the menu item plays `.selection`);
    /// the removal itself plays `.dismiss`.
    func playlistSongRemovalConfirmation(
        _ pending: Binding<PendingPlaylistSongRemoval>,
        playlistName: String,
        onConfirm: @escaping (Song) -> Void
    ) -> some View {
        confirmationDialog(
            "Remove Song?",
            isPresented: pending.isPresented,
            titleVisibility: .visible,
            presenting: pending.wrappedValue.song
        ) { song in
            Button("Remove", role: .destructive) {
                AppHaptic.dismiss.play()
                onConfirm(song)
            }
            Button("Cancel", role: .cancel) {}
        } message: { song in
            Text("Are you sure you want to remove \(song.title) from \(playlistName)?")
        }
    }
}
