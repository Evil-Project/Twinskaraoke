import SwiftUI

/// The song an Add to Playlist sheet was opened for, fixed when it opens.
///
/// The player's sheets were driven by a Bool and read the current song when
/// they drew. If playback moved on while one was open, the sheet swapped to
/// the next song under the user's finger, keeping the old song's checkmarks
/// in its `@State`, so a tap could add the wrong song. The full-screen player
/// papered over it by closing the sheet on every song change. Holding the
/// song itself, and presenting with `sheet(item:)`, keeps the sheet on the
/// song it was opened for.
struct AddToPlaylistPresenter {
    /// Non-nil while the sheet is up; the sheet's binding clears it on
    /// dismissal.
    var song: Song?

    /// Opens the sheet for `song`. Nil, as for a player with nothing
    /// loaded, opens nothing.
    mutating func present(_ song: Song?) {
        self.song = song
    }
}

extension View {
    /// Presents Add to Playlist for the song `presenter` captured.
    func addToPlaylistSheet(_ presenter: Binding<AddToPlaylistPresenter>) -> some View {
        sheet(item: presenter.song) { song in
            AddToPlaylistSheet(song: song)
        }
    }
}
