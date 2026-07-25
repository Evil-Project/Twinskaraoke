import SwiftUI

struct ArtThumbnail: View {
    let art: GalleryArt
    var body: some View {
        Group {
            if let url = art.imageURL {
                RemoteArtworkImage(
                    url: url, cornerRadius: 8, showsLoading: false, lowResURL: art.blurPreviewURL,
                    transparentBackground: true
                )
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let upvotes = art.upvotes, upvotes > 0 {
                Label("\(upvotes)", systemImage: "heart.fill")
                    .scaledSystemFont(size: 11, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(7)
            }
        }
    }
}
