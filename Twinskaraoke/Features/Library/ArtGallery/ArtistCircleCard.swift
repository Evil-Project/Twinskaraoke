import SwiftUI

struct ArtistCircleCard: View {
    let artist: GalleryArtist

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
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
                            Text(initials(artist.name))
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            Text(artist.name)
                .scaledSystemFont(size: 13, weight: .medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100)
        }
    }

    private func initials(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
