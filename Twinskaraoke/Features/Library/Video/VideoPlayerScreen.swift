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
    @Environment(\.scenePhase) private var scenePhase

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
                    resumedFrom: model.resumedFrom,
                    onExit: { isFullScreen = false },
                    onRetry: { model.reload() },
                    onStartFromBeginning: { model.startFromBeginning() },
                    onDismissResume: { model.dismissResumeBanner() }
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
            // Backgrounding never reaches `onDisappear`, and an app killed while
            // backgrounded never runs anything again, so this is the last chance
            // to write the playhead for the "exits the app" case.
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
                resumedFrom: model.resumedFrom,
                onToggleFullScreen: { isFullScreen = true },
                onRetry: { model.reload() },
                onStartFromBeginning: { model.startFromBeginning() },
                onDismissResume: { model.dismissResumeBanner() }
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
    let resumedFrom: TimeInterval?
    let onToggleFullScreen: () -> Void
    let onRetry: () -> Void
    let onStartFromBeginning: () -> Void
    let onDismissResume: () -> Void

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
                .animation(AppMotion.easeInOut(duration: 0.18), value: visibilityTracker.isUserInterfaceHidden)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { visibilityTracker.toggle() }
        // Deliberately outside the visibility-gated overlay: the banner is a
        // timed notice about what just happened, not a transport control, so
        // tapping to hide the controls must not take it away with them.
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

/// Says where playback picked up, and offers the way out of it.
///
/// Resuming silently is the wrong default for a gallery: a viewer who opens a
/// video expecting the start needs to see that it did something else, and needs
/// one tap to undo it.
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
            // The inline surface is only as wide as a 16:9 box on a phone, so
            // the notice has to give way rather than push the actions off it.
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
                    // 24pt is well under the 44pt minimum touch target, and
                    // "Start Over" sits one 10pt gap away, so a mis-tap
                    // restarted the video instead of dismissing the notice.
                    // The padding takes the tappable area to 44pt and is then
                    // removed from layout again, so the banner keeps its
                    // height and the mark keeps its size. 10pt on the leading
                    // side fills exactly the stack's spacing, leaving the two
                    // targets adjacent rather than overlapping.
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
