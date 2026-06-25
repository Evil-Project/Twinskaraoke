import SwiftUI

struct FeaturedArtCard: View {
    let art: GalleryArt
    let artist: GalleryArtist

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = art.imageURL {
                    RemoteArtworkImage(
                        url: url, cornerRadius: 16, showsLoading: false, lowResURL: art.blurPreviewURL,
                        transparentBackground: true
                    )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                }
            }
            .aspectRatio(4 / 5, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 4) {
                Text("FEATURED ART")
                    .scaledSystemFont(size: 11, weight: .bold)
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(0.6)
                Text(artist.name)
                    .scaledSystemFont(size: 22, weight: .bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let upvotes = art.upvotes, upvotes > 0 {
                    Label("\(upvotes)", systemImage: "heart.fill")
                        .scaledSystemFont(size: 13, weight: .semibold)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.top, 2)
                }
            }
            .padding(20)
        }
    }
}
