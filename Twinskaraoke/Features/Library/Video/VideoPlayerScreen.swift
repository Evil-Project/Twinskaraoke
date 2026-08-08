import AVFoundation
import Combine
import PillarboxPlayer
import SwiftUI

struct VideoPlayerScreen: View {
    let video: GalleryVideo

    @Namespace private var zoomNamespace
    // Reuses the model Pillarbox is holding for an active Picture in Picture
    // overlay, so returning to a video already playing in PiP resumes that
    // player rather than starting a second one.
    @StateObject private var model = VideoPlaybackModel()
    @StateObject private var progressTracker = ProgressTracker(interval: .init(value: 1, timescale: 10))
    @StateObject private var visibilityTracker = VisibilityTracker()
    @State private var similar = SimilarVideosViewModel()
    @State private var quality: VideoQuality = .auto
    @State private var gravity: AVLayerVideoGravity = .resizeAspect
    @State private var isFullScreen = false
    @State private var appeared = false
    // `isBuffering` lives on `PlayerProperties`, which Pillarbox publishes
    // separately from the player's own `@Published` state, so it has to be
    // mirrored into view state rather than read off `player` directly.
    @State private var isBuffering = false

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion

    private let audioWillPlay = NotificationCenter.default.publisher(
        for: MediaPlaybackCoordinator.audioWillPlay
    )

    /// Landscape on iPhone. Tilting is the primary way into full screen; the
    /// button is the explicit alternative and works in portrait too.
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
            // Full screen is a *presentation*, not a layout swap. Hiding the tab
            // bar from a pushed screen is not enough: with LNPopupController
            // attached, the minimised tab pill and the `role: .search` button
            // keep drawing over the video, and the mini player merges into the
            // tab bar's own metrics. A full-screen presentation sits above all
            // of it by construction — the same conclusion `PlaylistDetailView`
            // reached for its editor.
            .fullScreenCover(isPresented: $isFullScreen) {
                VideoFullScreenPlayer(
                    player: model.player,
                    progressTracker: progressTracker,
                    visibilityTracker: visibilityTracker,
                    quality: $quality,
                    gravity: $gravity,
                    isBuffering: isBuffering,
                    onExit: { isFullScreen = false },
                    onRetry: { model.reload() }
                )
            }
            // Tilting the device enters and leaves full screen.
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
            .onReceive(audioWillPlay) { _ in
                model.player.pause()
            }
            .onChange(of: quality) { _, quality in
                model.quality = quality
            }
            .onReceive(player: model.player, assign: \.isBuffering, to: $isBuffering)
    }

    // MARK: - Layout

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

    /// The inline surface stands down while the full-screen cover is up.
    ///
    /// An `AVPlayerLayer` can only be attached to one player at a time, so
    /// leaving a second `VideoView` alive underneath the cover would steal the
    /// layer back and leave one of the two black.
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
                onToggleFullScreen: { isFullScreen = true },
                onRetry: { model.reload() }
            )
        }
    }

    // MARK: - Playback

    private func start() {
        progressTracker.player = model.player
        visibilityTracker.player = model.player
        quality = model.quality

        // False when this screen was restored onto a video already playing in
        // Picture in Picture, which must not be interrupted or restarted.
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

/// The full-screen presentation: nothing but the video and its controls.
private struct VideoFullScreenPlayer: View {
    @ObservedObject var player: Player
    @ObservedObject var progressTracker: ProgressTracker
    @ObservedObject var visibilityTracker: VisibilityTracker
    @Binding var quality: VideoQuality
    @Binding var gravity: AVLayerVideoGravity
    let isBuffering: Bool
    let onExit: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VideoPlayerSurface(
            player: player,
            progressTracker: progressTracker,
            visibilityTracker: visibilityTracker,
            quality: $quality,
            gravity: $gravity,
            isBuffering: isBuffering,
            isFullScreen: true,
            onToggleFullScreen: onExit,
            onRetry: onRetry
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .allowsLandscapeOrientation()
    }
}

/// Stands in for the video while it is playing in the full-screen cover.
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

/// The video surface and its controls.
///
/// Split out so it can observe the `Player` directly. The player is owned by
/// `VideoPlaybackModel` (which has to outlive the screen for Picture in
/// Picture), and reaching through an unobserved model would leave `error` and
/// `playbackState` changes unnoticed.
private struct VideoPlayerSurface: View {
    @ObservedObject var player: Player
    @ObservedObject var progressTracker: ProgressTracker
    @ObservedObject var visibilityTracker: VisibilityTracker
    @Binding var quality: VideoQuality
    @Binding var gravity: AVLayerVideoGravity
    let isBuffering: Bool
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            // Deliberately no `.supportsPictureInPicture()`. That path makes
            // `VideoView` build Picture in Picture host views on every player
            // publish, and this screen tears the surface down and rebuilds it
            // when entering and leaving the full-screen cover — which churned
            // AVKit's PiP observers and could wedge playback on pause or exit.
            // Supporting PiP properly needs a restoration delegate and an entry
            // point in the UI; see the note in VideoPlaybackModel.
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
                .animation(.easeInOut(duration: 0.18), value: visibilityTracker.isUserInterfaceHidden)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { visibilityTracker.toggle() }
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
