import SwiftUI

/// Edit and Delete for the user's own uploads, carried down to the shared
/// song menu.
///
/// Passed through the environment, as `PlaylistSongRemovalContext` is:
/// `SongRow` and `SongActionsMenuItems` are used on many screens, and only
/// the Uploaded screen supplies these. Where nothing injects them the value
/// stays nil and the menu has neither item.
struct UploadedSongMenuActions {
    enum Item: CaseIterable {
        case edit
        case delete
    }

    let edit: (Song) -> Void
    let delete: (Song) -> Void

    /// The items the song menu adds: Edit and Delete when a screen supplied
    /// `actions`, none otherwise.
    static func items(offeredBy actions: UploadedSongMenuActions?) -> [Item] {
        actions == nil ? [] : Item.allCases
    }
}

private struct UploadedSongMenuActionsKey: EnvironmentKey {
    // Computed, so the non-Sendable closures don't become shared state.
    static var defaultValue: UploadedSongMenuActions? { nil }
}

extension EnvironmentValues {
    /// Non-nil only for rows of the Uploaded screen.
    var uploadedSongMenuActions: UploadedSongMenuActions? {
        get { self[UploadedSongMenuActionsKey.self] }
        set { self[UploadedSongMenuActionsKey.self] = newValue }
    }
}
