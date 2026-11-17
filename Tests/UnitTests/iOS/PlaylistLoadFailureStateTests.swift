import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
struct PlaylistDetailEmptyStateTests {
    /// The failure was read out of the message's English prefix, so in any
    /// other language a failed load read as an empty playlist.
    @Test func aFailedLoadIsReportedWhateverTheMessageSays() {
        let message = "Die Playlist konnte nicht geladen werden."
        for isFavorites in [false, true] {
            let state = PlaylistDetailEmptyState(isFavorites: isFavorites, loadFailed: true, message: message)
            #expect(state.title == String(localized: "Couldn't Load Songs"))
            #expect(state.message == message)
            #expect(state.actionTitle == String(localized: "Try Again"))
        }
    }

    @Test func anEmptyFavouritesListExplainsHowToFillIt() {
        let state = PlaylistDetailEmptyState(isFavorites: true, loadFailed: false, message: "Tap refresh.")
        #expect(state.title == String(localized: "No Favorites Yet"))
        #expect(state.message == String(localized: "Favorite songs to build this playlist automatically."))
        #expect(state.actionTitle == String(localized: "Refresh"))
    }

    @Test func anEmptyPlaylistKeepsTheLoadersMessage() {
        let state = PlaylistDetailEmptyState(isFavorites: false, loadFailed: false, message: "Tap refresh.")
        #expect(state.title == String(localized: "No Songs"))
        #expect(state.message == "Tap refresh.")
        #expect(state.actionTitle == String(localized: "Refresh"))
    }
}

struct PlaylistsGridContentTests {
    private func resolve(
        isLoading: Bool = false,
        hasPlaylists: Bool = true,
        hasMatches: Bool = true,
        isSignedIn: Bool = true,
        loadFailed: Bool = false
    ) -> PlaylistsGridContent {
        .resolve(
            isLoading: isLoading,
            hasPlaylists: hasPlaylists,
            hasMatches: hasMatches,
            isSignedIn: isSignedIn,
            loadFailed: loadFailed
        )
    }

    /// Signed in, the grid always holds Favourite Songs, so a failed
    /// playlists request left that tile alone with nothing saying why.
    @Test func aFailedLoadBesideLocalPlaylistsShowsTheNotice() {
        #expect(resolve(loadFailed: true) == .playlists(showsLoadNotice: true))
        #expect(resolve() == .playlists(showsLoadNotice: false))
    }

    @Test func aFailedLoadWithNothingToShowIsAFailureNotAnEmptyLibrary() {
        #expect(resolve(hasPlaylists: false, hasMatches: false, loadFailed: true) == .loadFailed)
        #expect(resolve(hasPlaylists: false, hasMatches: false) == .noPlaylists)
    }

    @Test func signedOutAskForSignInRatherThanARetry() {
        #expect(resolve(hasPlaylists: false, hasMatches: false, isSignedIn: false, loadFailed: true) == .signInRequired)
    }

    @Test func loadingAndSearchStatesAreUnchanged() {
        #expect(resolve(isLoading: true, hasPlaylists: false, hasMatches: false) == .loading)
        #expect(resolve(isLoading: true) == .playlists(showsLoadNotice: false))
        #expect(resolve(hasMatches: false) == .noResults)
    }
}
