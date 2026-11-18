import SwiftUI

struct CategoryTile: View {
    let title: String
    let gradient: [Color]
    var artworkURL: URL?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var optimizedArtworkURL: URL? {
        guard let artworkURL else { return nil }
        return ArtworkURLBuilder.variantURL(from: artworkURL, variant: .thumbnail) ?? artworkURL
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let artworkURL = optimizedArtworkURL {
                RemoteArtworkImage(url: artworkURL, cornerRadius: 0, contentMode: .fill)
                    .allowsHitTesting(false)
                LinearGradient(
                    colors: gradient.map { $0.opacity(0.70) },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            } else {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                .padding(AM.Spacing.m)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .allowsHitTesting(false)
        }
        .frame(height: isCompactWidth ? 92 : 102)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
    }
}
