import Testing
@testable import Twinskaraoke

@MainActor
struct AddToPlaylistPresenterTests {
    private let first = UITestFixtures.song(id: "first", title: "First", artist: "A")
    private let next = UITestFixtures.song(id: "next", title: "Next", artist: "B")

    /// The player's sheets read the current song when they drew, so an
    /// auto-advance swapped the song under an open sheet. The presenter holds
    /// the song it opened for; the current song moving on doesn't touch it.
    @Test func theSheetKeepsTheSongItOpenedFor() {
        var currentSong: Song? = first
        var presenter = AddToPlaylistPresenter()

        presenter.present(currentSong)
        currentSong = next

        #expect(presenter.song == first)
        #expect(presenter.song != currentSong)
    }

    @Test func nothingPlayingOpensNothing() {
        var presenter = AddToPlaylistPresenter()
        presenter.present(nil)
        #expect(presenter.song == nil)
    }
}
