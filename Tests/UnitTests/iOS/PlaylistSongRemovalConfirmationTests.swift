import Testing
@testable import Twinskaraoke

/// Removing a song from a playlist asks first, from the song's context menu
/// as from Add to Playlist. The menu item used to remove straight away.
struct PlaylistSongRemovalConfirmationTests {
    private let song = Song(
        id: "remove-me", title: "Hero", duration: 180, absolutePath: nil,
        cloudflareID: nil, coverArt: nil, originalArtists: ["Mili"], coverArtists: nil, userUploaded: false
    )

    @Test func askingToRemoveASongPresentsTheConfirmation() {
        var pending = PendingPlaylistSongRemoval()
        #expect(!pending.isPresented)

        pending.request(song)

        #expect(pending.isPresented)
        #expect(pending.song?.id == "remove-me")
    }

    @Test func dismissingTheConfirmationForgetsTheSong() {
        var pending = PendingPlaylistSongRemoval()
        pending.request(song)

        pending.isPresented = false

        #expect(pending.song == nil)
    }
}
