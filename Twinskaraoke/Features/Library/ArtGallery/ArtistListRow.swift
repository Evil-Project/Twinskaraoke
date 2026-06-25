import SwiftUI

struct ArtistListRow: View {
    let artist: GalleryArtist

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let art = artist.arts?.first, let url = art.imageURL {
                    RemoteArtworkImage(
                        url: url, cornerRadius: 100, showsLoading: false, lowResURL: art.blurPreviewURL,
                        transparentBackground: true
                    )
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Text(String(artist.name.first ?? "?").uppercased())
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .scaledSystemFont(size: 16, weight: .medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(artist.arts?.count ?? 0) artworks")
                    .scaledSystemFont(size: 13)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .scaledSystemFont(size: 13, weight: .semibold)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
