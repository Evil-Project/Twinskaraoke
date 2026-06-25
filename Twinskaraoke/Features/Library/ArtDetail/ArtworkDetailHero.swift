import SwiftUI

struct ArtworkDetailHero: View {
    let art: GalleryArt
    let artist: GalleryArtist
    let fullResURL: URL?
    let onOpen: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            ArtworkDetailAmbientBackground(art: art)

            LinearGradient(
                colors: [
                    Color.appBackground.opacity(0.08),
                    Color.appBackground.opacity(0.72),
                    Color.appBackground,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 16) {
                Button(action: onOpen) {
                    heroArtwork
                }
                .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.86))
                .contextMenu {
                    if let fullResURL {
                        ShareLink(item: fullResURL) {
                            Label("Share Artwork", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(action: onSave) {
                        Label("Save Artwork", systemImage: "square.and.arrow.down")
                    }
                    if let upvotes = art.upvotes, upvotes > 0 {
                        Label("\(upvotes) likes", systemImage: "heart.fill")
                    }
                } preview: {
                    ArtworkDetailContextPreview(art: art, artist: artist)
                }

                VStack(spacing: 6) {
                    Text(artist.name)
                        .scaledSystemFont(size: 30, weight: .bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let social = trimmed(artist.socialLink) {
                        Text(social)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    if let upvotes = art.upvotes, upvotes > 0 {
                        ArtworkDetailPill(systemImage: "heart.fill", title: "\(upvotes)", tint: .pink)
                    }
                    if trimmed(art.credit) != nil {
                        ArtworkDetailPill(systemImage: "person.crop.square", title: "Credits", tint: .blue)
                    }
                    if fullResURL != nil {
                        ArtworkDetailPill(systemImage: "photo", title: "HD", tint: Color.appAccent)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 430)
    }

    @ViewBuilder
    private var heroArtwork: some View {
        if let url = fullResURL {
            RemoteArtworkImage(
                url: url,
                cornerRadius: 20,
                contentMode: .fit,
                showsLoading: false,
                lowResURL: art.blurPreviewURL,
                transparentBackground: true
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 285)
            .shadow(color: Color.appHeroShadowPlaying, radius: 24, y: 12)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.46), in: Circle())
                    .padding(12)
            }
        } else {
            MusicArtworkPlaceholder(cornerRadius: 20)
                .frame(maxWidth: 285)
                .aspectRatio(1, contentMode: .fit)
        }
    }
}
