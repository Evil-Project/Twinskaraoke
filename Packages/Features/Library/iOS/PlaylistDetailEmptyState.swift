import Foundation

/// What a playlist screen with no songs to show says, and what its button
/// does.
///
/// A failed load is reported by the loader, not read out of the message: the
/// view used to test `message.hasPrefix("The playlist")`, which is only true
/// in English, so every other language showed a failed load as an empty
/// playlist, and Favourites as "Favorite songs to build this playlist".
struct PlaylistDetailEmptyState: Equatable {
    let title: String
    let message: String
    let actionTitle: String

    init(isFavorites: Bool, loadFailed: Bool, message: String) {
        if loadFailed {
            title = String(localized: "Couldn't Load Songs")
            self.message = message
            actionTitle = String(localized: "Try Again")
        } else if isFavorites {
            title = String(localized: "No Favorites Yet")
            self.message = String(localized: "Favorite songs to build this playlist automatically.")
            actionTitle = String(localized: "Refresh")
        } else {
            title = String(localized: "No Songs")
            self.message = message
            actionTitle = String(localized: "Refresh")
        }
    }
}
