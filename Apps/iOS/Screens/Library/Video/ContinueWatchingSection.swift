import SwiftUI
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
            VideoThumbnail(video: video, cornerRadius: AM.Radius.card)
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
            .frame(width: 208, height: 52, alignment: .topLeading)
        }
    }
}
