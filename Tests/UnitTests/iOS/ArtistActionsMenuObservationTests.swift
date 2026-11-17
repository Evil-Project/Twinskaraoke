import Testing
@testable import Twinskaraoke

/// `ArtistActionsMenu` is built inside the artist screen's `Menu` and
/// `contextMenu` closures, which run while the *screen's* body runs. Any
/// download state it derives in `init` is a tracked `DownloadManager` read on
/// the screen's behalf, subscribing the whole artist screen to every download
/// that starts or finishes. The menu may only hold its songs; download state
/// is read in its own body.
///
/// Structural rather than behavioural: `DownloadManager` has no test-safe way
/// to change its published state, so the subscription itself can't be
/// triggered from a unit test.
@MainActor
struct ArtistActionsMenuObservationTests {
    @Test func theMenuStoresOnlyItsSongs() {
        let menu = ArtistActionsMenu(songs: [
            Song(
                id: "song",
                title: "Song",
                duration: 180,
                absolutePath: nil,
                cloudflareID: nil,
                coverArt: nil,
                originalArtists: nil,
                coverArtists: nil,
                userUploaded: false
            ),
        ])

        let storedProperties = Mirror(reflecting: menu).children.compactMap(\.label)

        #expect(storedProperties == ["songs"])
    }
}
