import AVKit
import Combine
import SwiftUI

#if canImport(UIKit)
    import UIKit

    struct FullscreenAVPlayer: UIViewControllerRepresentable {
        let player: AVPlayer
        func makeUIViewController(context _: Context) -> AVPlayerViewController {
            let vc = AVPlayerViewController()
            vc.player = player
            vc.allowsPictureInPicturePlayback = true
            vc.canStartPictureInPictureAutomaticallyFromInline = true
            vc.entersFullScreenWhenPlaybackBegins = false
            vc.exitsFullScreenWhenPlaybackEnds = false
            vc.showsPlaybackControls = true
            vc.videoGravity = .resizeAspect
            return vc
        }

        func updateUIViewController(_ uiViewController: AVPlayerViewController, context _: Context) {
            if uiViewController.player !== player {
                uiViewController.player = player
            }
        }
    }
#endif

struct VideoGalleryView: View {
    @StateObject private var viewModel = VideoGalleryViewModel()
    private let cols = AM.Layout.adaptiveGridColumns(minimum: 164, spacing: 16)
    var body: some View {
        ScrollView {
            if viewModel.videos.isEmpty, viewModel.isLoading {
                VideoGallerySkeleton()
                    .padding(.top, 16)
            } else if let message = viewModel.errorMessage, viewModel.videos.isEmpty {
                VideoGalleryStateView(
                    title: "Couldn't Load Videos",
                    message: message,
                    buttonTitle: "Try Again"
                ) {
                    viewModel.refresh()
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.videos.isEmpty {
                VideoGalleryStateView(
                    title: "No Videos",
                    message: "Recent Twinskaraoke videos will appear here.",
                    buttonTitle: "Refresh"
                ) {
                    viewModel.refresh()
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if let featured = viewModel.videos.first {
                VStack(alignment: .leading, spacing: 24) {
                    NavigationLink(value: LibraryDestination.video(featured)) {
                        FeaturedVideoCard(video: featured)
                    }
                    .buttonStyle(PressableButtonStyle(haptic: .selection))
                    .contextMenu {
                        VideoActionsMenu(video: featured)
                    } preview: {
                        VideoContextPreview(video: featured, isFeatured: true)
                    }
                    .padding(.horizontal, 16)
                    if viewModel.videos.count > 1 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Recent Videos")
                                    .scaledSystemFont(size: 22, weight: .bold)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            LazyVGrid(columns: cols, spacing: 20) {
                                ForEach(viewModel.videos.dropFirst()) { video in
                                    NavigationLink(value: LibraryDestination.video(video)) {
                                        VideoGalleryCell(video: video)
                                    }
                                    .buttonStyle(PressableButtonStyle(haptic: .selection))
                                    .contextMenu {
                                        VideoActionsMenu(video: video)
                                    } preview: {
                                        VideoContextPreview(video: video)
                                    }
                                    .onAppear { viewModel.loadMoreIfNeeded(current: video) }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.regular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .scrollIndicators(.hidden)
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle("Video Gallery")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            AppHaptic.selection.play()
            viewModel.refresh()
        }
        .onAppear { viewModel.fetchInitial() }
    }
}

private struct VideoThumbnail: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(
                Group {
                    if let url {
                        RemoteArtworkImage(url: url, cornerRadius: cornerRadius)
                    } else {
                        MusicArtworkPlaceholder(cornerRadius: cornerRadius)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct FeaturedVideoCard: View {
    let video: GalleryVideo
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                VideoThumbnail(url: video.thumbnailURL, cornerRadius: 14)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LATEST VIDEO")
                            .scaledSystemFont(size: 11, weight: .bold)
                            .foregroundColor(.white.opacity(0.85))
                            .tracking(0.5)
                        Text(video.songTitle ?? video.name)
                            .scaledSystemFont(size: 17, weight: .semibold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct VideoGalleryCell: View {
    let video: GalleryVideo
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoThumbnail(url: video.thumbnailURL, cornerRadius: 10)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.songTitle ?? video.name)
                    .scaledSystemFont(size: 14, weight: .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let creator = video.createdBy, !creator.isEmpty {
                    Text(creator)
                        .scaledSystemFont(size: 12)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VideoGallerySkeleton: View {
    var body: some View {
        CenteredLoadingView(label: "Loading videos")
    }
}

private struct VideoGalleryStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let onRefresh: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var hasAppeared = false


    var body: some View {
        VStack(spacing: AM.Spacing.xl) {
            MusicEmptyStateMark()
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.03 : 0.98))
                .scaleEffect(reduceMotion ? 1 : (hasAppeared ? 1 : 0.94))
                .opacity(hasAppeared ? 1 : 0)

            VStack(spacing: AM.Spacing.s) {
                Text(title)
                    .scaledSystemFont(size: 23, weight: .bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .scaledSystemFont(size: 15)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: 340)

            MusicEmptyActionButton(title: buttonTitle) {
                AppHaptic.selection.play()
                onRefresh()
            }

            VStack(spacing: AM.Spacing.s) {
                VideoGalleryHintRow(
                    title: "Karaoke videos",
                    message: "New uploads from the Twinskaraoke feed appear here."
                )
                VideoGalleryHintRow(
                    title: "Refresh the feed",
                    message: "Pull down or tap retry when the video service is slow."
                )
            }
            .frame(maxWidth: 360)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (hasAppeared ? 0 : 10))
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
        .onAppear {
            guard !reduceMotion else {
                hasAppeared = true
                isPulsing = false
                return
            }
            withAnimation(AppMotion.standard) {
                hasAppeared = true
            }
            withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion {
                withAnimation(nil) {
                    isPulsing = false
                    hasAppeared = true
                }
            } else {
                withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct VideoGalleryHintRow: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: AM.Spacing.m) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledSystemFont(size: 14, weight: .semibold)
                    .foregroundColor(.primary)
                Text(message)
                    .scaledSystemFont(size: 13)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AM.Spacing.m)
        .padding(.vertical, AM.Spacing.s)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
    }
}

private extension GalleryVideo {
    var displayTitle: String {
        songTitle ?? name
    }

    var shareURL: URL? {
        embedURL ?? streamURL ?? thumbnailURL
    }

    var trimmedCreator: String? {
        videoTrimmed(createdBy)
    }

    var trimmedCreatedDate: String? {
        videoTrimmed(createdDate)
    }
}

private func videoTrimmed(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private struct VideoActionsMenu: View {
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

private struct VideoContextPreview: View {
    let video: GalleryVideo
    var isFeatured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoThumbnail(url: video.thumbnailURL, cornerRadius: 12)
                .frame(width: 252)
            VStack(alignment: .leading, spacing: 4) {
                if isFeatured {
                    Text("Latest Video")
                        .scaledSystemFont(size: 11, weight: .bold)
                        .foregroundColor(.appAccent)
                }
                Text(video.displayTitle)
                    .scaledSystemFont(size: 17, weight: .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if let creator = video.createdBy, !creator.isEmpty {
                    Text(creator)
                        .scaledSystemFont(size: 14)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(width: 284, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VideoPlayerScreen: View {
    let video: GalleryVideo
    @State private var player: AVPlayer?
    @State private var appeared = false
    @StateObject private var similar = SimilarVideosViewModel()
    @Environment(\.appReduceMotion) private var reduceMotion
    private let audioWillPlay = NotificationCenter.default.publisher(
        for: MediaPlaybackCoordinator.audioWillPlay
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Group {
                    #if canImport(UIKit)
                        if let player {
                            FullscreenAVPlayer(player: player)
                        } else {
                            ZStack {
                                Color.black
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(.white)
                            }
                        }
                    #else
                        if let player {
                            VideoPlayer(player: player)
                        } else {
                            ZStack {
                                Color.black
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(.white)
                            }
                        }
                    #endif
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
                .contextMenu {
                    VideoActionsMenu(video: video)
                } preview: {
                    VideoContextPreview(video: video, isFeatured: true)
                }

                VideoPlayerInfoPanel(video: video)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (appeared ? 0 : 14))

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
                        .padding(.horizontal, 16)
                        LazyVStack(spacing: 0) {
                            ForEach(Array(similar.videos.enumerated()), id: \.element.id) { idx, item in
                                NavigationLink(value: LibraryDestination.video(item)) {
                                    SimilarVideoRow(video: item)
                                }
                                .buttonStyle(PressableButtonStyle(haptic: .selection))
                                .contextMenu {
                                    VideoActionsMenu(video: item)
                                } preview: {
                                    VideoContextPreview(video: item)
                                }
                                if idx < similar.videos.count - 1 {
                                    Divider().padding(.leading, 16 + 140 + 12)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (appeared ? 0 : 10))
                } else if similar.isLoading {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
        }
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle(video.songTitle ?? "Video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = video.shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share video")
                }
            }
        }
        .onAppear {
            startPlaybackIfNeeded()
            similar.fetch(excluding: video.id)
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(AppMotion.standard) {
                appeared = true
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion {
                withAnimation(nil) {
                    appeared = true
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onReceive(audioWillPlay) { _ in
            player?.pause()
        }
    }

    private func startPlaybackIfNeeded() {
        guard player == nil, let url = video.streamURL ?? video.embedURL else { return }
        AudioPlayerManager.shared.pauseIfPlaying()
        let nextPlayer = AVPlayer(url: url)
        NotificationCenter.default.post(
            name: MediaPlaybackCoordinator.videoWillPlay, object: nil
        )
        nextPlayer.play()
        player = nextPlayer
        AppHaptic.light.play()
    }
}

private struct VideoPlayerInfoPanel: View {
    let video: GalleryVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Now Playing", systemImage: "play.circle.fill")
                    .scaledSystemFont(size: 12, weight: .bold)
                    .foregroundStyle(Color.appAccent)
                    .textCase(.uppercase)
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

            VideoPlayerActionRow(video: video)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VideoMetadataPills: View {
    let video: GalleryVideo

    var body: some View {
        HStack(spacing: 8) {
            if let creator = video.trimmedCreator {
                VideoMetadataPill(systemImage: "person.fill", title: creator)
            }
            if let date = video.trimmedCreatedDate {
                VideoMetadataPill(systemImage: "calendar", title: date)
            }
            if video.streamURL != nil {
                VideoMetadataPill(systemImage: "dot.radiowaves.left.and.right", title: "Stream")
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
                    VideoActionButtonLabel(systemImage: "square.and.arrow.up", title: "Share")
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))

                #if canImport(UIKit)
                    Button {
                        AppHaptic.selection.play()
                        UIPasteboard.general.url = url
                    } label: {
                        VideoActionButtonLabel(systemImage: "link", title: "Copy")
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

private struct SimilarVideoRow: View {
    let video: GalleryVideo
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VideoThumbnail(url: video.thumbnailURL, cornerRadius: 8)
                .frame(width: 140)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.songTitle ?? video.name)
                    .scaledSystemFont(size: 14, weight: .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let creator = video.createdBy, !creator.isEmpty {
                    Text(creator)
                        .scaledSystemFont(size: 12)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
