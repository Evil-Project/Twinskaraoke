import AVFoundation
import Combine
import PillarboxPlayer
import SwiftUI

extension VideoQuality {
    /// Expressed as a resolution ceiling rather than a pinned variant playlist,
    /// so the player can still adapt *below* the ceiling when the connection
    /// degrades instead of stalling on a rung it cannot sustain.
    var playerLimits: PlayerLimits {
        guard let maximumResolution else { return .none }
        return PlayerLimits(preferredMaximumResolution: maximumResolution)
    }
}

struct VideoPlayerScreen: View {
    let video: GalleryVideo

    @Namespace private var zoomNamespace
    @StateObject private var player = Player(configuration: .videoGallery)
    @StateObject private var progressTracker = ProgressTracker(interval: .init(value: 1, timescale: 10))
    @StateObject private var visibilityTracker = VisibilityTracker()
    @State private var similar = SimilarVideosViewModel()
    @State private var quality: VideoQuality = .auto
    @State private var gravity: AVLayerVideoGravity = .resizeAspect
    @State private var isManuallyFullScreen = false
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

    /// Landscape on iPhone. Tilting the device is the primary way into full
    /// screen; the button is the explicit alternative.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var isFullScreen: Bool { isManuallyFullScreen || isLandscape }

    var body: some View {
        Group {
            if isFullScreen {
                fullScreenLayout
            } else {
                inlineLayout
            }
        }
        .allowsLandscapeOrientation()
        .videoFullScreenState(isFullScreen)
        .navigationTitle(video.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        // Hides the search button too — it is a `role: .search` tab, so it is
        // part of the tab bar rather than a separate overlay.
        .toolbar(isFullScreen ? .hidden : .visible, for: .tabBar)
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
        .statusBarHidden(isFullScreen)
        .onAppear { start() }
        .onDisappear {
            player.pause()
            visibilityTracker.player = nil
            progressTracker.player = nil
        }
        .onReceive(audioWillPlay) { _ in
            player.pause()
        }
        .onChange(of: quality) { _, quality in
            player.limits = quality.playerLimits
        }
        .onReceive(player: player, assign: \.isBuffering, to: $isBuffering)
        .animation(reduceMotion ? nil : AppMotion.standard, value: isFullScreen)
    }

    // MARK: - Layouts

    private var fullScreenLayout: some View {
        playerSurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
    }

    private var inlineLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                playerSurface
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

    private var playerSurface: some View {
        ZStack {
            VideoView(player: player)
                .gravity(gravity)
                .supportsPictureInPicture()

            if let error = player.error {
                VideoPlaybackErrorView(error: error) { start(force: true) }
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
                    onToggleFullScreen: toggleFullScreen
                )
                .opacity(visibilityTracker.isUserInterfaceHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.18), value: visibilityTracker.isUserInterfaceHidden)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { visibilityTracker.toggle() }
    }

    // MARK: - Playback

    private func start(force: Bool = false) {
        guard let url = video.streamURL else { return }
        if !force, player.currentItem != nil { return }

        AudioPlayerManager.shared.pauseIfPlaying()
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.videoWillPlay, object: nil)

        player.limits = quality.playerLimits
        player.items = [
            .simple(
                url: url,
                metadata: PlayerMetadata(
                    title: video.displayTitle,
                    subtitle: video.createdBy,
                    description: video.description,
                    imageSource: video.posterURL.map { .url(standardResolution: $0) } ?? .none
                )
            ),
        ]
        progressTracker.player = player
        visibilityTracker.player = player
        player.becomeActive()
        player.play()

        similar.fetch(like: video)

        AppHaptic.commit.play()
        guard !reduceMotion else {
            appeared = true
            return
        }
        withAnimation(AppMotion.standard) { appeared = true }
    }

    private func toggleFullScreen() {
        // Tilting is what normally drives full screen, so the button only ever
        // controls the portrait case; in landscape there is nothing to toggle
        // back to without fighting the device orientation.
        guard !isLandscape else { return }
        isManuallyFullScreen.toggle()
    }
}

private extension PlayerConfiguration {
    /// Gallery videos are on-demand, so playback should stop at the end rather
    /// than advance, and the position is worth restoring when a video is
    /// reopened from the same session.
    static let videoGallery = PlayerConfiguration(
        allowsExternalPlayback: true,
        usesExternalPlaybackWhileMirroring: false,
        backwardSkipInterval: 10,
        forwardSkipInterval: 10
    )
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
