import SwiftUI

struct GalleryStatsStrip: View {
    let artistCount: Int
    let artworkCount: Int
    let totalUpvotes: Int

    var body: some View {
        HStack(spacing: 0) {
            stat(value: "\(artistCount)", label: artistCount == 1 ? "Artist" : "Artists")
            Divider().frame(height: 30)
            stat(value: "\(artworkCount)", label: artworkCount == 1 ? "Artwork" : "Artworks")
            Divider().frame(height: 30)
            stat(value: "\(totalUpvotes)", label: totalUpvotes == 1 ? "Like" : "Likes")
        }
        .padding(.vertical, 12)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .scaledSystemFont(size: 18, weight: .bold)
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
