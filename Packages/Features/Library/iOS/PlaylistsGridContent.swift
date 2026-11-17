import Foundation

/// What the Library's Playlists screen shows.
///
/// A failed playlists request used to be invisible here: the screen showed
/// "No Playlists", or the Favourite Songs tile on its own, as if the account
/// had none.
enum PlaylistsGridContent: Equatable {
    case loading
    case signInRequired
    case loadFailed
    case noPlaylists
    case noResults
    /// `showsLoadNotice`: the playlists request failed, so the grid holds
    /// only what is known locally (Favourite Songs, saved playlists).
    case playlists(showsLoadNotice: Bool)

    /// - Parameters:
    ///   - hasPlaylists: anything to show before the search filter applies.
    ///   - hasMatches: anything left after it. Fewer matches than
    ///     playlists only happens while searching.
    static func resolve(
        isLoading: Bool,
        hasPlaylists: Bool,
        hasMatches: Bool,
        isSignedIn: Bool,
        loadFailed: Bool
    ) -> Self {
        if isLoading, !hasPlaylists { return .loading }
        // Signed out, a failure is the expected outcome, and signing in is
        // the way forward rather than retrying.
        if !hasPlaylists, !isSignedIn { return .signInRequired }
        if !hasPlaylists, loadFailed { return .loadFailed }
        if !hasMatches { return hasPlaylists ? .noResults : .noPlaylists }
        return .playlists(showsLoadNotice: loadFailed)
    }
}
