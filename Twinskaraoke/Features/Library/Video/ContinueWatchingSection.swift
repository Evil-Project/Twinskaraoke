import SwiftUI

/// Videos the viewer started but did not finish, newest first.
///
/// Rendered straight from `VideoResumeStore` rather than from the gallery feed:
/// the feed pages 25 at a time through ~1400 videos, so anything watched more
/// than a few days ago is almost never among the pages currently loaded. The
/// store keeps the `GalleryVideo` alongside the position for exactly this.
struct ContinueWatchingSection: View {
    let zoomNamespace: Namespace.ID

    private var points: [VideoResumePoint] {
        VideoResumeStore.shared.continueWatching
    }

    var body: some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(points) { point in
                            // The id is prefixed because the same video can also
                            // be on screen in the grid below, and two zoom
                            // transition sources sharing one id in one namespace
                            // is ambiguous.
                            ZoomNavigationLink(id: "continue-\(point.id)", in: zoomNamespace) {
                                VideoPlayerScreen(video: point.video)
                            } label: {
                                ContinueWatchingCard(point: point)
                            }
                            .buttonStyle(PressableButtonStyle(haptic: .selection))
                            .contextMenu {
                                VideoActionsMenu(video: point.video)
                                Divider()
                                Button(role: .destructive) {
                                    AppHaptic.selection.play()
                                    VideoResumeStore.shared.clear(videoID: point.id)
                                } label: {
                                    Label("Remove from Continue Watching", systemImage: "minus.circle")
                                }
                            } preview: {
                                VideoContextPreview(video: point.video)
                            }
                        }
                    }
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    // Cards lift under `PressableButtonStyle`, and a LazyHStack
                    // clips to its own bounds without room to grow into.
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .smoothScrolling()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Continue Watching")
                .scaledSystemFont(size: 22, weight: .bold)
            Spacer()
            Menu {
                Button(role: .destructive) {
                    AppHaptic.selection.play()
                    VideoResumeStore.shared.clearContinueWatching()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Continue Watching options")
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
    }
}

private struct ContinueWatchingCard: View {
    let point: VideoResumePoint

    private var video: GalleryVideo { point.video }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoThumbnail(video: video, cornerRadius: 10)
                .frame(width: 208)
                .overlay(alignment: .bottomLeading) {
                    if let remaining = point.remaining {
                        Text("\(VideoTimecodeFormatter.string(fromSeconds: Int(remaining.rounded()))) left")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                .black.opacity(0.72),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                            .padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
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
            }
            // Two title lines plus a creator line, so cards in a row keep their
            // posters aligned whatever the title length.
            .frame(width: 208, height: 52, alignment: .topLeading)
        }
    }
}
