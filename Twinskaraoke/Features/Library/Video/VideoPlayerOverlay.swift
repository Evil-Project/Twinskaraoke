import AVFoundation
import PillarboxPlayer
import SwiftUI

/// Transport controls drawn over the video surface.
///
/// Everything here is custom because the system player UI cannot host a quality
/// selector on iOS — `SystemVideoView.transportBar` is tvOS-only — and quality
/// control is the main thing the previous `AVPlayerViewController` could not
/// offer. Track selection, playback speed, zoom and AirPlay still come from
/// Pillarbox's own `standardSettingsMenu`, so only the quality section and the
/// layout are hand-written.
struct VideoPlayerOverlay: View {
    @ObservedObject var player: Player
    @ObservedObject var progressTracker: ProgressTracker
    @Binding var quality: VideoQuality
    @Binding var gravity: AVLayerVideoGravity
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack {
                topBar
                Spacer(minLength: 0)
                transportButtons
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, isFullScreen ? 28 : 12)
            .padding(.vertical, isFullScreen ? 18 : 10)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            settingsMenu
        }
    }

    private var settingsMenu: some View {
        Menu {
            Section("Quality") {
                Picker("Quality", selection: $quality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.inline)
            }
            player.standardSettingsMenu()
        } label: {
            VideoOverlayGlyph(systemImage: "ellipsis", size: 17)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Playback settings")
    }

    private var transportButtons: some View {
        HStack(spacing: isFullScreen ? 52 : 36) {
            Button {
                AppHaptic.selection.play()
                player.skipBackward()
            } label: {
                VideoOverlayGlyph(systemImage: "gobackward.10", size: isFullScreen ? 30 : 24)
            }
            .disabled(!player.canSkipBackward())
            .accessibilityLabel("Skip back 10 seconds")

            Button {
                AppHaptic.commit.play()
                player.togglePlayPause()
            } label: {
                VideoOverlayGlyph(
                    systemImage: player.playbackState == .playing ? "pause.fill" : "play.fill",
                    size: isFullScreen ? 42 : 34
                )
            }
            .accessibilityLabel(player.playbackState == .playing ? "Pause" : "Play")

            Button {
                AppHaptic.selection.play()
                player.skipForward()
            } label: {
                VideoOverlayGlyph(systemImage: "goforward.10", size: isFullScreen ? 30 : 24)
            }
            .disabled(!player.canSkipForward())
            .accessibilityLabel("Skip forward 10 seconds")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if progressTracker.isProgressAvailable {
                Slider(progressTracker: progressTracker)
                    .tint(.white)
            }
            HStack(spacing: 12) {
                Text(elapsedText)
                    .videoTimecodeStyle()
                Spacer(minLength: 0)
                Text(remainingText)
                    .videoTimecodeStyle()
                Button {
                    AppHaptic.selection.play()
                    onToggleFullScreen()
                } label: {
                    VideoOverlayGlyph(
                        systemImage: isFullScreen
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                        size: 16
                    )
                }
                .accessibilityLabel(isFullScreen ? "Exit full screen" : "Enter full screen")
            }
        }
    }

    private var elapsedText: String {
        Self.timecode(progressTracker.time)
    }

    private var remainingText: String {
        let remaining = progressTracker.timeRange.end - progressTracker.time
        guard remaining.isNumeric else { return "--:--" }
        return "-\(Self.timecode(remaining))"
    }

    private static func timecode(_ time: CMTime) -> String {
        guard time.isNumeric else { return "--:--" }
        return VideoTimecodeFormatter.string(fromSeconds: Int(time.seconds.rounded()))
    }
}

private struct VideoOverlayGlyph: View {
    let systemImage: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

private extension View {
    func videoTimecodeStyle() -> some View {
        font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

