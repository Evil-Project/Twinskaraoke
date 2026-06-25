import SwiftUI

struct GalleryArtPreview: View {
    let art: GalleryArt
    let artist: GalleryArtist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArtThumbnail(art: art)
                .frame(width: 220, height: 220)
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .scaledSystemFont(size: 17, weight: .semibold)
                    .lineLimit(1)
                if let upvotes = art.upvotes, upvotes > 0 {
                    Label("\(upvotes) likes", systemImage: "heart.fill")
                        .scaledSystemFont(size: 13, weight: .medium)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 248, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
