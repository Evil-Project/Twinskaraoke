import SwiftUI

struct ArtistArtsView: View {
    let artist: GalleryArtist
    @Environment(\.appReduceMotion) private var reduceMotion
    private let cols = AM.Layout.adaptiveGridColumns(minimum: 148, spacing: 10)
    private var arts: [GalleryArt] {
        artist.arts ?? []
    }

    private var heroArt: GalleryArt? {
        arts.first
    }

    private var totalUpvotes: Int {
        arts.reduce(0) { $0 + ($1.upvotes ?? 0) }
    }


    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ArtistArtsHero(
                    artist: artist,
                    art: heroArt,
                    artworkCount: arts.count,
                    totalUpvotes: totalUpvotes
                )
                if !arts.isEmpty {
                    HStack {
                        Text("Artwork")
                            .scaledSystemFont(size: 22, weight: .bold)
                        Spacer()
                        Text("\(arts.count)")
                            .scaledSystemFont(size: 14, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)

                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(arts) { art in
                            NavigationLink {
                                ArtDetailView(art: art, artist: artist)
                            } label: {
                                ArtThumbnail(art: art)
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.82, haptic: .selection))
                            .contextMenu {
                                if let url = art.fullHDImageURL ?? art.imageURL {
                                    ShareLink(item: url) {
                                        Label("Share Artwork", systemImage: "square.and.arrow.up")
                                    }
                                }
                                if let upvotes = art.upvotes, upvotes > 0 {
                                    Label("\(upvotes) likes", systemImage: "heart.fill")
                                }
                            } preview: {
                                ArtContextPreview(art: art, artist: artist)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                } else {
                    ArtistArtworkEmptyState(artistName: artist.name)
                        .padding(.top, 12)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .padding(.bottom, 16)
        }
        .smoothScrolling()
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .animation(
            reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84),
            value: arts.count
        )
    }
}

private struct ArtistArtsHero: View {
    let artist: GalleryArtist
    let art: GalleryArt?
    let artworkCount: Int
    let totalUpvotes: Int
    private var imageURL: URL? {
        art?.imageURL
    }

    private var lowResURL: URL? {
        art?.blurPreviewURL
    }

    var body: some View {
        ZStack {
            Group {
                if let imageURL {
                    RemoteArtworkImage(
                        url: imageURL,
                        cornerRadius: 0,
                        contentMode: .fill,
                        showsLoading: false,
                        lowResURL: lowResURL,
                        transparentBackground: true
                    )
                    .blur(radius: 24)
                    .opacity(0.45)
                    .scaleEffect(1.08)
                } else {
                    LinearGradient(
                        colors: [Color.appAccent.opacity(0.32), Color.appSecondaryBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                colors: [Color.appBackground.opacity(0.15), Color.appBackground.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 14) {
                HeroArtwork(art: art, artistName: artist.name)
                VStack(spacing: 5) {
                    Text(artist.name)
                        .scaledSystemFont(size: 28, weight: .bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let social = artist.socialLink, !social.isEmpty {
                        Text(social)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                ArtistArtsStatsRow(artworkCount: artworkCount, totalUpvotes: totalUpvotes)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 390)
    }
}

private struct HeroArtwork: View {
    let art: GalleryArt?
    let artistName: String

    var body: some View {
        Group {
            if let art, let url = art.imageURL {
                RemoteArtworkImage(
                    url: url,
                    cornerRadius: 18,
                    showsLoading: false,
                    lowResURL: art.blurPreviewURL,
                    transparentBackground: true
                )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.appAccent.opacity(0.85), Color.pink.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Text(initial(artistName))
                            .font(.system(size: 70, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
        .frame(width: 230, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.appHeroShadowPlaying, radius: 20, y: 10)
    }

    private func initial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

private struct ArtistArtsStatsRow: View {
    let artworkCount: Int
    let totalUpvotes: Int

    var body: some View {
        HStack(spacing: 8) {
            ArtistArtsStatPill(value: "\(artworkCount)", label: artworkCount == 1 ? "Artwork" : "Artworks")
            ArtistArtsStatPill(value: "\(totalUpvotes)", label: totalUpvotes == 1 ? "Like" : "Likes")
        }
    }
}

private struct ArtistArtsStatPill: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.appControlInactiveFill, in: Capsule())
    }
}

private struct ArtistArtworkEmptyState: View {
    let artistName: String

    var body: some View {
        VStack(spacing: 14) {
            MusicEmptyState(
                title: "No Artwork Yet",
                message: "Artwork credited to \(artistName) will appear here."
            )
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.appPlaceholderPrimary)
                    .frame(width: 12, height: 12)
                Text("Follow the artist gallery for new covers as they arrive.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.appControlInactiveFill, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

struct ArtThumbnail: View {
    let art: GalleryArt
    var body: some View {
        Group {
            if let url = art.imageURL {
                RemoteArtworkImage(
                    url: url, cornerRadius: 8, showsLoading: false, lowResURL: art.blurPreviewURL,
                    transparentBackground: true
                )
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let upvotes = art.upvotes, upvotes > 0 {
                Label("\(upvotes)", systemImage: "heart.fill")
                    .scaledSystemFont(size: 11, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(7)
            }
        }
        .shadow(color: Color.appShadow.opacity(0.7), radius: 8, y: 4)
    }
}

private struct ArtContextPreview: View {
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
