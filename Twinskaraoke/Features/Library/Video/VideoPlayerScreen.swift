import AVFoundation
import PillarboxPlayer
import SwiftUI

struct VideoPlayerScreen: View {
    let video: GalleryVideo

    @Namespace private var zoomNamespace
    @StateObject private var model = VideoPlaybackModel()
    @StateObject private var progressTracker = ProgressTracker(interval: .init(value: 1, timescale: 10))
    @StateObject private var visibilityTracker = VisibilityTracker()
    @State private var similar = SimilarVideosViewModel()
    @State private var quality: VideoQuality = .auto
    @State private var gravity: AVLayerVideoGravity = .resizeAspect
    @State private var isFullScreen = false
    @State private var appeared = false
    @State private var isBuffering = false

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let audioWillPlay = NotificationCenter.default.publisher(
        for: MediaPlaybackCoordinator.audioWillPlay
    )
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        inlineLayout
            .allowsLandscapeOrientation()
            .videoFullScreenState(isFullScreen)
            .navigationTitle(video.displayTitle)
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
            .fullScreenCover(isPresented: $isFullScreen) {
                VideoFullScreenPlayer(
                    player: model.player,
                    progressTracker: progressTracker,
                    visibilityTracker: visibilityTracker,
                    quality: $quality,
                    gravity: $gravity,
                    isBuffering: isBuffering,
                    resumedFrom: model.resumedFrom,
                    onExit: { isFullScreen = false },
                    onRetry: { model.reload() },
                    onStartFromBeginning: { model.startFromBeginning() },
                    onDismissResume: { model.dismissResumeBanner() }
                )
            }
            .onChange(of: isLandscape) { _, isLandscape in
                guard isFullScreen != isLandscape else { return }
                isFullScreen = isLandscape
            }
            .onAppear { start() }
            .onDisappear {
                model.pause()
                visibilityTracker.player = nil
                progressTracker.player = nil
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                model.persistPosition()
            }
            .onReceive(audioWillPlay) { _ in
                model.player.pause()
            }
            .onChange(of: quality) { _, quality in
                model.quality = quality
            }
            .onReceive(player: model.player, assign: \.isBuffering, to: $isBuffering)
    }

    private var inlineLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                inlinePlayerSurface
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(.black)
                    .contextMenu {
                        VideoActionsMenu(video: video)
                    }

                VideoPlayerInfoPanel(video: video)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .padding(.top, 18)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (appeared ? 0 : 14))

                SimilarVideosSection(
                    similar: similar,
                    zoomNamespace: zoomNamespace
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (appeared ? 0 : 10))
            }
        }
        .smoothScrolling()
        .musicScreenBackground()
    }
    @ViewBuilder
    private var inlinePlayerSurface: some View {
        if isFullScreen {
            VideoInlinePlaceholder(video: video)
        } else {
            VideoPlayerSurface(
                player: model.player,
                progressTracker: progressTracker,
                visibilityTracker: visibilityTracker,
                quality: $quality,
                gravity: $gravity,
                isBuffering: isBuffering,
                isFullScreen: false,
                resumedFrom: model.resumedFrom,
                onToggleFullScreen: { isFullScreen = true },
                onRetry: { model.reload() },
                onStartFromBeginning: { model.startFromBeginning() },
                onDismissResume: { model.dismissResumeBanner() }
            )
        }
    }

    private func start() {
        progressTracker.player = model.player
        visibilityTracker.player = model.player
        quality = model.quality
        if model.load(video) {
            AudioPlayerManager.shared.pauseIfPlaying()
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.videoWillPlay, object: nil)
            model.play()
            AppHaptic.commit.play()
        }

        similar.fetch(like: video)

        guard !reduceMotion else {
            appeared = true
            return
        }
        withAnimation(AppMotion.standard) { appeared = true }
    }
}
private struct VideoFullScreenPlayer: View {
    @ObservedObject var player: Player
    @ObservedObject var progressTracker: ProgressTracker
    @ObservedObject var visibilityTracker: VisibilityTracker
    @Binding var quality: VideoQuality
    @Binding var gravity: AVLayerVideoGravity
    let isBuffering: Bool
    let resumedFrom: TimeInterval?
    let onExit: () -> Void
    let onRetry: () -> Void
    let onStartFromBeginning: () -> Void
    let onDismissResume: () -> Void

    var body: some View {
        VideoPlayerSurface(
            player: player,
            progressTracker: progressTracker,
            visibilityTracker: visibilityTracker,
            quality: $quality,
            gravity: $gravity,
            isBuffering: isBuffering,
            isFullScreen: true,
            resumedFrom: resumedFrom,
            onToggleFullScreen: onExit,
            onRetry: onRetry,
            onStartFromBeginning: onStartFromBeginning,
            onDismissResume: onDismissResume
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .allowsLandscapeOrientation()
    }
}
private struct VideoInlinePlaceholder: View {
    let video: GalleryVideo

    var body: some View {
        ZStack {
            Color.black
            if let url = video.thumbnailURL {
                RemoteArtworkImage(url: url, cornerRadius: 0)
                    .opacity(0.35)
            }
            Label("Playing full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                .scaledSystemFont(size: 13, weight: .semibold)
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
private struct VideoPlayerSurface: View {
    @ObservedObject var player: Player
    @ObservedObject var progressTracker: ProgressTracker
    @ObservedObject var visibilityTracker: VisibilityTracker
    @Binding var quality: VideoQuality
    @Binding var gravity: AVLayerVideoGravity
    let isBuffering: Bool
    let isFullScreen: Bool
    let resumedFrom: TimeInterval?
    let onToggleFullScreen: () -> Void
    let onRetry: () -> Void
    let onStartFromBeginning: () -> Void
    let onDismissResume: () -> Void

    var body: some View {
        ZStack {
            VideoView(player: player)
                .gravity(gravity)

            if let error = player.error {
                VideoPlaybackErrorView(error: error, onRetry: onRetry)
            } else {
                ProgressView()
                    .tint(.white)
                    .opacity(isBuffering ? 1 : 0)
                    .animation(.linear(duration: 0.1), value: isBuffering)

                VideoPlayerOverlay(
                    player: player,
                    progressTracker: progressTracker,
                    quality: $quality,
                    gravity: $gravity,
                    isFullScreen: isFullScreen,
                    onToggleFullScreen: onToggleFullScreen
                )
                .opacity(visibilityTracker.isUserInterfaceHidden ? 0 : 1)
                .animation(AppMotion.easeInOut(duration: 0.18), value: visibilityTracker.isUserInterfaceHidden)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { visibilityTracker.toggle() }
        .overlay(alignment: .topLeading) {
            if let resumedFrom, player.error == nil {
                VideoResumeBanner(
                    position: resumedFrom,
                    onStartFromBeginning: onStartFromBeginning,
                    onDismiss: onDismissResume
                )
                .padding(isFullScreen ? 28 : 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AppMotion.quick, value: resumedFrom)
    }
}
private struct VideoResumeBanner: View {
    let position: TimeInterval
    let onStartFromBeginning: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(
                "Resumed from \(VideoTimecodeFormatter.string(fromSeconds: Int(position.rounded())))",
                systemImage: "clock.arrow.circlepath"
            )
            .scaledSystemFont(size: 12, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Button {
                AppHaptic.selection.play()
                onStartFromBeginning()
            } label: {
                Text("Start Over")
                    .scaledSystemFont(size: 12, weight: .bold)
                    .foregroundStyle(Color.appAccent)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityHint("Plays this video from the beginning")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .padding(10)
                    .contentShape(Rectangle())
                    .padding(-10)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .padding(.vertical, 6)
        .background(.black.opacity(0.72), in: Capsule())
    }
}

private struct VideoPlaybackErrorView: View {
    let error: Error
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AM.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.9))
            Text("This video couldn't be played")
                .scaledSystemFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)
            Text(error.localizedDescription)
                .scaledSystemFont(size: 13)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button {
                AppHaptic.selection.play()
                onRetry()
            } label: {
                Text("Try Again")
                    .scaledSystemFont(size: 14, weight: .semibold)
                    .padding(.horizontal, AM.Spacing.l)
                    .padding(.vertical, AM.Spacing.s)
                    .background(.white.opacity(0.18), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(AM.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
    }
}
