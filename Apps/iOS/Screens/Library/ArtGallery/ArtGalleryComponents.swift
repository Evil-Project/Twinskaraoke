import SwiftUI

// MARK: - ArtGalleryEmptyState

struct ArtGalleryEmptyState: View {
    let isError: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            MusicEmptyState(
                title: isError ? String(localized: "Artwork Couldn't Load") : String(localized: "No Artwork Yet"),
                message: isError
                    ? String(localized: "Check your connection and try loading the gallery again.")
                    : String(localized: "New cover art and artist galleries will appear here.")
            )
            MusicEmptyActionButton(title: isError ? String(localized: "Try Again") : String(localized: "Refresh")) {
                onRefresh()
            }
        }
    }
}

// MARK: - ArtGallerySkeletonView

struct ArtGallerySkeletonView: View {
    var body: some View {
        CenteredLoadingView(label: String(localized: "Loading art gallery"))
    }
}

// MARK: - ArtistCircleCard

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

// MARK: - ArtistListRow

struct ArtistListRow: View {
    let artist: GalleryArtist

    var body: some View {
        HStack(spacing: 14) {
            Group {
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
                            Text(String(artist.name.first ?? "?").uppercased())
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .scaledSystemFont(size: 16, weight: .medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(artist.arts?.count ?? 0) artworks")
                    .scaledSystemFont(size: 13)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .scaledSystemFont(size: 13, weight: .semibold)
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - FeaturedArtCard

struct FeaturedArtCard: View {
    let art: GalleryArt
    let artist: GalleryArtist

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = art.imageURL {
                    RemoteArtworkImage(
                        url: url, cornerRadius: 16, lowResURL: art.blurPreviewURL,
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
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 4) {
                Text("FEATURED ART")
                    .scaledSystemFont(size: 11, weight: .bold)
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(0.6)
                Text(artist.name)
                    .scaledSystemFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let upvotes = art.upvotes, upvotes > 0 {
                    Label("\(upvotes)", systemImage: "heart.fill")
                        .scaledSystemFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 2)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - GalleryArtPreview

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
        .appGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - GallerySectionHeader

struct GallerySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .scaledSystemFont(size: 22, weight: .bold)
            .padding(.horizontal, 16)
    }
}

// MARK: - GalleryStatsStrip

struct GalleryStatsStrip: View {
    let artistCount: Int
    let artworkCount: Int
    let totalUpvotes: Int

    var body: some View {
        HStack(spacing: 0) {
            stat(value: artistCount.formatted(), label: artistCount == 1 ? String(localized: "Artist") : String(localized: "Artists"))
            Divider().frame(height: 30)
            stat(value: artworkCount.formatted(), label: artworkCount == 1 ? String(localized: "Artwork") : String(localized: "Artworks"))
            Divider().frame(height: 30)
            stat(value: totalUpvotes.formatted(), label: totalUpvotes == 1 ? String(localized: "Like") : String(localized: "Likes"))
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
