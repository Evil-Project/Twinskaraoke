import SwiftUI

struct ArtThumbnail: View {
    let art: GalleryArt
    var body: some View {
        Group {
            if let url = art.imageURL {
                RemoteArtworkImage(
                    url: url, cornerRadius: AM.Radius.card, lowResURL: art.blurPreviewURL,
                    transparentBackground: true
                )
            } else {
                RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let upvotes = art.upvotes, upvotes > 0 {
                Label("\(upvotes)", systemImage: "heart.fill")
                    .scaledSystemFont(size: 11, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(7)
            }
        }
    }
}
