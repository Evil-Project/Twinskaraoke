import SwiftUI

struct ArtGalleryEmptyState: View {
    let isError: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            MusicEmptyState(
                title: isError ? "Artwork Couldn't Load" : "No Artwork Yet",
                message: isError
                    ? "Check your connection and try loading the gallery again."
                    : "New cover art and artist galleries will appear here."
            )
            MusicEmptyActionButton(title: isError ? "Try Again" : "Refresh") {
                onRefresh()
            }
        }
    }
}
