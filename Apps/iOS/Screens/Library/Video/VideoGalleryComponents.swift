import SwiftUI

extension GalleryVideo {
    var shareURL: URL? {
        embedURL ?? streamURL ?? posterURL
    }

    var trimmedCreator: String? {
        videoTrimmed(createdBy)
    }

    var trimmedDescription: String? {
        videoTrimmed(description)
    }
    var formattedCreatedDate: String? {
        guard let createdDate, let date = VideoDateParser.date(from: createdDate) else { return nil }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}

private func videoTrimmed(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

nonisolated enum VideoDateParser {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func date(from string: String) -> Date? {
        let normalized = string.hasSuffix("Z") ? string : string + "Z"
        return (try? fractional.parse(normalized)) ?? (try? plain.parse(normalized))
    }
}

nonisolated enum VideoCountFormatter {
    static func string(from count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    /// "1 view", "12 views", "1.2K views". The single view is its own string
    /// because the count reaches the catalogue already formatted, as text,
    /// which plural rules cannot be applied to.
    ///
    /// A `Text` built from keys, not a resolved `String`, so the lookup
    /// happens in the locale environment the app's language setting controls.
    static func viewsText(_ count: Int) -> Text {
        count == 1 ? Text("1 view") : Text("\(string(from: count)) views")
    }
}

struct VideoThumbnail: View {
    let video: GalleryVideo
    var cornerRadius: CGFloat = 10
    var showsBadges = true
    var showsProgress = true
    private var watchedFraction: Double? {
        VideoResumeStore.shared.point(for: video.id)?.fraction
    }

    private var isWatched: Bool {
        VideoResumeStore.shared.isWatched(video.id)
    }

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(
                Group {
                    if let url = video.thumbnailURL {
                        RemoteArtworkImage(url: url, cornerRadius: cornerRadius)
                    } else {
                        MusicArtworkPlaceholder(cornerRadius: cornerRadius)
                    }
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if showsBadges, showsProgress, isWatched {
                    VideoWatchedBadge()
                        .padding(6)
                } else if showsBadges, let runtime = video.formattedRuntime {
                    Text(runtime)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsBadges, video.isWatchalongVideo {
                    Label("Watchalong", systemImage: "popcorn.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.appAccent.opacity(0.92), in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if showsProgress, let watchedFraction {
                    VideoResumeProgressBar(fraction: watchedFraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
struct VideoWatchedBadge: View {
    var body: some View {
        Label("Watched", systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.72), in: Capsule())
    }
}
struct VideoResumeProgressBar: View {
    let fraction: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.45))
                Rectangle()
                    .fill(Color.appAccent)
                    .frame(width: max(2, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .accessibilityLabel("Watch progress")
        .accessibilityValue(Text(fraction.formatted(.percent.precision(.fractionLength(0)))))
    }
}

struct VideoActionsMenu: View {
    let video: GalleryVideo

    var body: some View {
        if let url = video.shareURL {
            ShareLink(item: url) {
                Label("Share Video", systemImage: "square.and.arrow.up")
            }

            #if canImport(UIKit)
                Button {
                    AppHaptic.selection.play()
                    UIPasteboard.general.url = url
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            #endif
        } else {
            Label("No Link Available", systemImage: "link.badge.plus")
        }
    }
}

struct VideoContextPreview: View {
    let video: GalleryVideo
    var isFeatured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoThumbnail(video: video, cornerRadius: AM.Radius.card)
                .frame(width: 252)
            VStack(alignment: .leading, spacing: 4) {
                if isFeatured {
                    Text("Latest Video")
                        .scaledSystemFont(size: 11, weight: .bold)
                        .foregroundStyle(Color.appAccent)
                }
                Text(video.displayTitle)
                    .scaledSystemFont(size: 17, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let creator = video.trimmedCreator {
                    Text(creator)
                        .scaledSystemFont(size: 14)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(width: 284, alignment: .leading)
        .appGlassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VideoPlayerInfoPanel: View {
    let video: GalleryVideo
    @State private var isDescriptionExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(video.displayTitle)
                    .scaledSystemFont(size: 25, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if video.name != video.displayTitle {
                    Text(video.name)
                        .scaledSystemFont(size: 14)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            VideoMetadataPills(video: video)

            if let description = video.trimmedDescription {
                VStack(alignment: .leading, spacing: 6) {
                    Text(description)
                        .scaledSystemFont(size: 14)
                        .foregroundStyle(.secondary)
                        .lineLimit(isDescriptionExpanded ? nil : 3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        AppHaptic.selection.play()
                        withAnimation(AppMotion.standard) { isDescriptionExpanded.toggle() }
                    } label: {
                        Text(isDescriptionExpanded ? "Show Less" : "Show More")
                            .scaledSystemFont(size: 13, weight: .semibold)
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }

            VideoPlayerActionRow(video: video)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VideoMetadataPills: View {
    let video: GalleryVideo

    var body: some View {
        HStack(spacing: 8) {
            if let creator = video.trimmedCreator {
                VideoMetadataPill(systemImage: "person.fill", title: creator)
            }
            if let views = video.views, views > 0 {
                VideoMetadataPill(
                    systemImage: "eye.fill",
                    title: VideoCountFormatter.string(from: views)
                )
            }
            if let upvotes = video.upvotes, upvotes > 0 {
                VideoMetadataPill(
                    systemImage: "hand.thumbsup.fill",
                    title: VideoCountFormatter.string(from: upvotes)
                )
            }
            if let date = video.formattedCreatedDate {
                VideoMetadataPill(systemImage: "calendar", title: date)
            }
        }
    }
}

private struct VideoMetadataPill: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.appControlInactiveFill, in: Capsule())
    }
}

private struct VideoPlayerActionRow: View {
    let video: GalleryVideo

    var body: some View {
        if let url = video.shareURL {
            HStack(spacing: 10) {
                ShareLink(item: url) {
                    VideoActionButtonLabel(systemImage: "square.and.arrow.up", title: String(localized: "Share"))
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))

                #if canImport(UIKit)
                    Button {
                        AppHaptic.selection.play()
                        UIPasteboard.general.url = url
                    } label: {
                        VideoActionButtonLabel(systemImage: "link", title: String(localized: "Copy"))
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
                #endif
            }
        }
    }
}

private struct VideoActionButtonLabel: View {
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

struct SimilarVideosSection: View {
    let similar: SimilarVideosViewModel
    let zoomNamespace: Namespace.ID

    var body: some View {
        if !similar.videos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Similar Videos")
                        .scaledSystemFont(size: 20, weight: .bold)
                    Spacer()
                    Text("\(similar.videos.count)")
                        .scaledSystemFont(size: 13, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, AM.Spacing.screenMargin)
                LazyVStack(spacing: 0) {
                    ForEach(Array(similar.videos.enumerated()), id: \.element.id) { idx, item in
                        ZoomNavigationLink(id: item.id, in: zoomNamespace) {
                            VideoPlayerScreen(video: item)
                        } label: {
                            SimilarVideoRow(video: item)
                        }
                        .buttonStyle(PressableButtonStyle(haptic: .selection))
                        .contextMenu {
                            VideoActionsMenu(video: item)
                        } preview: {
                            VideoContextPreview(video: item)
                        }
                        if idx < similar.videos.count - 1 {
                            Divider().padding(.leading, AM.Spacing.screenMargin + 140 + 12)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, AM.Spacing.l)
        } else if similar.isLoading {
            ProgressView()
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }
}

private struct SimilarVideoRow: View {
    let video: GalleryVideo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VideoThumbnail(video: video, cornerRadius: AM.Radius.card)
                .frame(width: 140)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.displayTitle)
                    .scaledSystemFont(size: 14, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let creator = video.trimmedCreator {
                    Text(creator)
                        .scaledSystemFont(size: 12)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let views = video.views, views > 0 {
                    VideoCountFormatter.viewsText(views)
                        .scaledSystemFont(size: 12)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)
            Spacer()
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
