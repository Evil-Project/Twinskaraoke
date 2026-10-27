import SwiftUI

struct ArtGalleryEmptyState: View {
    let isError: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            MusicEmptyState(
                title: isError ? String(localized: "Artwork Couldn't Load") : String(localized: "No Artwork Yet"),
                message: isError
                    ? String(localized: "Check your connection and try loading the gallery again.")
                    : String(localized: "New cover art and artist galleries will appear here.")
            )
            MusicEmptyActionButton(title: isError ? String(localized: "Try Again") : String(localized: "Refresh")) {
                onRefresh()
            }
        }
    }
}
