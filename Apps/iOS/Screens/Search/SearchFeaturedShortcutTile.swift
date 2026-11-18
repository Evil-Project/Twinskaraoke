import SwiftUI

struct SearchFeaturedShortcutTile: View {
    let title: String
    var subtitle: String?
    let gradient: [Color]
    var artworkURL: URL?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var optimizedArtworkURL: URL? {
        guard let artworkURL else { return nil }
        return ArtworkURLBuilder.variantURL(from: artworkURL, variant: .card) ?? artworkURL
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            LinearGradient(
                colors: [Color.black.opacity(0.02), Color.black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
            .shadow(color: .black.opacity(0.34), radius: 4, x: 0, y: 1)
            .padding(AM.Spacing.l)
            .allowsHitTesting(false)
        }
        .frame(height: isCompactWidth ? 124 : 144)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        if let artworkURL = optimizedArtworkURL {
            RemoteArtworkImage(url: artworkURL, cornerRadius: 0, contentMode: .fill)
                .allowsHitTesting(false)
            LinearGradient(
                colors: gradient.map { $0.opacity(0.76) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        } else {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
        }
    }
}
