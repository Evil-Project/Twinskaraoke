import Foundation
import SwiftUI

// MARK: - ArtDetailStringHelpers

func trimmed(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

// MARK: - ArtworkActionLabel

struct ArtworkActionLabel: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .scaledSystemFont(size: 15, weight: .semibold)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - ArtworkActionStrip

struct ArtworkActionStrip: View {
    let url: URL?
    let saveStatus: ArtworkSaveStatus
    let onOpen: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                ArtworkActionLabel(systemImage: "arrow.up.left.and.arrow.down.right", title: String(localized: "View"))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))

            Button(action: onSave) {
                ArtworkSaveActionLabel(status: saveStatus)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
            .disabled(saveStatus.isSaving)

            if let url {
                ShareLink(item: url) {
                    ArtworkActionLabel(systemImage: "square.and.arrow.up", title: String(localized: "Share"))
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
            }
        }
    }
}

// MARK: - ArtworkDetailAmbientBackground

struct ArtworkDetailAmbientBackground: View {
    let art: GalleryArt

    var body: some View {
        ZStack {
            Color.appBackground
            if let url = art.imageURL {
                RemoteArtworkImage(
                    url: url,
                    cornerRadius: 0,
                    contentMode: .fill,
                    lowResURL: art.blurPreviewURL,
                    transparentBackground: true
                )
                .blur(radius: 28)
                .opacity(0.36)
                .scaleEffect(1.12)
            }
        }
        .clipped()
    }
}

// MARK: - ArtworkDetailContextPreview

struct ArtworkDetailContextPreview: View {
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

// MARK: - ArtworkDetailHero

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
                        ArtworkDetailPill(systemImage: "person.crop.square", title: String(localized: "Credits"), tint: .blue)
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
        if let url = art.heroImageURL ?? fullResURL ?? art.imageURL {
            RemoteArtworkImage(
                url: url,
                cornerRadius: 20,
                contentMode: .fit,
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

// MARK: - ArtworkDetailMetadata

struct ArtworkDetailMetadata: View {
    let art: GalleryArt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let description = trimmed(art.description) {
                ArtworkDetailSection(title: String(localized: "About"), text: description)
            }
            if let credit = trimmed(art.credit) {
                ArtworkDetailSection(title: String(localized: "Credits"), text: credit)
            }
            if let fileName = trimmed(art.fileName) {
                ArtworkDetailSection(title: String(localized: "File"), text: fileName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ArtworkDetailPill

struct ArtworkDetailPill: View {
    let systemImage: String
    let title: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.appControlInactiveFill, in: Capsule())
    }
}

// MARK: - ArtworkDetailSection

struct ArtworkDetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .scaledSystemFont(size: 13, weight: .semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .scaledSystemFont(size: 15, weight: .regular)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        }
    }
}

// MARK: - ArtworkSaveActionLabel

struct ArtworkSaveActionLabel: View {
    let status: ArtworkSaveStatus

    var body: some View {
        Group {
            switch status {
            case .saving:
                Label {
                    Text("Saving")
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
            case .success:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label("Retry", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .idle:
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
        .scaledSystemFont(size: 15, weight: .semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - ArtworkSaveStatus

enum ArtworkSaveStatus: Equatable {
    case idle
    case saving
    case success
    case failed(String)

    var isSaving: Bool {
        if case .saving = self { return true }
        return false
    }

    var accessibilityLabel: String {
        switch self {
        case .saving:
            String(localized: "Saving artwork")
        case .success:
            String(localized: "Artwork saved")
        case .failed:
            String(localized: "Artwork save failed")
        case .idle:
            String(localized: "Save artwork")
        }
    }
}
