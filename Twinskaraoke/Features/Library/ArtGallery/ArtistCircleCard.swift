import SwiftUI

struct ArtistCircleCard: View {
    let artist: GalleryArtist

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let art = artist.arts?.first, let url = art.imageURL(variant: .thumbnail) {
                    RemoteArtworkImage(
                        url: url, cornerRadius: 100, lowResURL: art.blurPreviewURL,
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
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            Text(artist.name)
                .scaledSystemFont(size: 13, weight: .medium)
                .foregroundStyle(.primary)
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
