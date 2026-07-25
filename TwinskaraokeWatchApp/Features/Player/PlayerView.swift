import SwiftUI

private struct WatchPlayerLayoutMetrics {
    let containerSize: CGSize

    private var compactWidth: Bool {
        containerSize.width < 180
    }

    private var compactHeight: Bool {
        containerSize.height < 205
    }

    var artworkSize: CGFloat {
        min(containerSize.width * (compactWidth ? 0.49 : 0.54), compactHeight ? 80 : 96)
    }

    var contentSpacing: CGFloat {
        compactHeight ? 6 : 9
    }

    var titleSize: CGFloat {
        compactWidth ? 13 : 14
    }

    var artistSize: CGFloat {
        compactWidth ? 10 : 11
    }

    var progressHorizontalPadding: CGFloat {
        compactWidth ? 2 : 4
    }

    var mainControlSpacing: CGFloat {
        compactWidth ? 9 : 13
    }

    var sideControlDiameter: CGFloat {
        compactWidth ? 31 : 34
    }

    var sideControlIconSize: CGFloat {
        compactWidth ? 14 : 15
    }

    var primaryControlDiameter: CGFloat {
        compactWidth ? 44 : 48
    }

    var primaryControlIconSize: CGFloat {
        compactWidth ? 22 : 24
    }

    var secondaryControlSpacing: CGFloat {
        compactWidth ? 12 : 18
    }

    var secondaryControlSize: CGFloat {
        compactWidth ? 26 : 28
    }

    var volumeHorizontalPadding: CGFloat {
        compactWidth ? 4 : 10
    }
}

struct PlayerView: View {
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var crownVolume = 1.0
    @State private var lastVolumeFeedbackStep: Int?

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var playbackAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    var body: some View {
        if let song = audioManager.currentSong {
            GeometryReader { geo in
                let metrics = WatchPlayerLayoutMetrics(containerSize: geo.size)
                ScrollView {
                    VStack(spacing: metrics.contentSpacing) {
                        ZStack {
                            WatchCachedImage(url: song.thumbnailURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.25))
                            }
                            .frame(width: metrics.artworkSize, height: metrics.artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                            .scaleEffect(reduceMotion ? 1 : (audioManager.isPlaying ? 1 : 0.95))
                            if audioManager.isLoading {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(overlayColor)
                                    .frame(width: metrics.artworkSize, height: metrics.artworkSize)
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(width: metrics.artworkSize, height: metrics.artworkSize)
                        .animation(playbackAnimation, value: audioManager.isPlaying)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Artwork")
                        .accessibilityValue(playerStateAccessibilityValue(for: song))
                        .accessibilityHint("Double tap to \(audioManager.isPlaying ? "pause" : "play").")
                        .accessibilityAction {
                            togglePlayPause()
                        }

                        VStack(spacing: 2) {
                            Text(song.title)
                                .font(.system(size: metrics.titleSize, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text(song.artistName)
                                .font(.system(size: metrics.artistSize))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Now Playing")
                        .accessibilityValue(playerStateAccessibilityValue(for: song))
                        .accessibilityHint("Use the playback controls below.")
                        VStack(spacing: 1) {
                            let total = max(audioManager.duration, 1)
                            ProgressView(value: min(audioManager.currentTime, total), total: total)
                                .tint(.secondary.opacity(0.8))
                                .scaleEffect(y: 0.6)
                            HStack {
                                Text(formatTime(audioManager.currentTime))
                                Spacer()
                                Text("-" + formatTime(max(0, audioManager.duration - audioManager.currentTime)))
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, metrics.progressHorizontalPadding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Playback Position")
                        .accessibilityValue(progressAccessibilityValue)
                        .accessibilityHint("Swipe up or down to seek by 15 seconds.")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment:
                                seek(by: 15)
                            case .decrement:
                                seek(by: -15)
                            @unknown default:
                                break
                            }
                        }

                        HStack(spacing: metrics.mainControlSpacing) {
                            WatchPlayerIconButton(
                                systemName: "backward.fill",
                                diameter: metrics.sideControlDiameter,
                                iconSize: metrics.sideControlIconSize,
                                tint: .primary,
                                fill: Color.secondary.opacity(0.14),
                                isDisabled: audioManager.isLoading,
                                accessibilityLabel: "Previous Track",
                                accessibilityValue: audioManager.isLoading ? "Unavailable while loading" : nil,
                                accessibilityHint: "Restarts the song or plays the previous track."
                            ) {
                                audioManager.playPrevious()
                                WatchHaptic.play(.previous)
                            }

                            WatchPlayerIconButton(
                                systemName: audioManager.isPlaying ? "pause.fill" : "play.fill",
                                diameter: metrics.primaryControlDiameter,
                                iconSize: metrics.primaryControlIconSize,
                                tint: .white,
                                fill: Color.appAccent,
                                accessibilityLabel: audioManager.isPlaying ? "Pause" : "Play",
                                accessibilityValue: audioManager.isLoading ? "Loading" : song.title,
                                accessibilityHint: audioManager.isPlaying ? "Pauses \(song.title)." : "Plays \(song.title)."
                            ) {
                                togglePlayPause()
                            }

                            WatchPlayerIconButton(
                                systemName: "forward.fill",
                                diameter: metrics.sideControlDiameter,
                                iconSize: metrics.sideControlIconSize,
                                tint: .primary,
                                fill: Color.secondary.opacity(0.14),
                                isDisabled: audioManager.isLoading,
                                accessibilityLabel: "Next Track",
                                accessibilityValue: audioManager.isLoading ? "Unavailable while loading" : nil,
                                accessibilityHint: "Skips to the next track."
                            ) {
                                audioManager.playNext()
                                WatchHaptic.play(.next)
                            }
                        }

                        HStack(spacing: metrics.secondaryControlSpacing) {
                            Button {
                                audioManager.toggleShuffle()
                                WatchHaptic.play(audioManager.isShuffleOn ? .success : .click)
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(audioManager.isShuffleOn ? .appAccent : .secondary)
                                    .frame(width: metrics.secondaryControlSize, height: metrics.secondaryControlSize)
                                    .background(
                                        Circle().fill(audioManager.isShuffleOn ? Color.appAccent.opacity(0.14) : Color.clear)
                                    )
                            }
                            .buttonStyle(.watchPressable)
                            .accessibilityLabel("Shuffle")
                            .accessibilityValue(audioManager.isShuffleOn ? "On" : "Off")
                            .accessibilityHint(audioManager.isShuffleOn ? "Turns shuffle off." : "Turns shuffle on.")
                            Button {
                                audioManager.toggleMode()
                                WatchHaptic.play(.click)
                            } label: {
                                Image(systemName: audioManager.playbackMode.iconName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(
                                        audioManager.playbackMode == .singleLoop ? .appAccent : .secondary
                                    )
                                    .frame(width: metrics.secondaryControlSize, height: metrics.secondaryControlSize)
                                    .background(
                                        Circle().fill(
                                            audioManager.playbackMode == .singleLoop
                                                ? Color.appAccent.opacity(0.14) : Color.clear
                                        )
                                    )
                            }
                            .buttonStyle(.watchPressable)
                            .accessibilityLabel("Repeat")
                            .accessibilityValue(
                                audioManager.playbackMode == .singleLoop ? "Repeat One" : "Repeat All"
                            )
                            .accessibilityHint("Cycles repeat mode.")
                            NavigationLink(destination: QueueView().environmentObject(audioManager)) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: metrics.secondaryControlSize, height: metrics.secondaryControlSize)
                            }
                            .buttonStyle(.watchPressable)
                            .accessibilityLabel("Playing Next")
                            .accessibilityValue(queueAccessibilityValue)
                            .accessibilityHint("Show the queue for \(song.title)")
                            .accessibilityIdentifier("WatchPlayer.queue")
                            .simultaneousGesture(TapGesture().onEnded { WatchHaptic.play(.click) })
                        }

                        WatchVolumeControl(volume: crownVolume) { newValue in
                            setVolume(newValue, feedback: true)
                        }
                        .padding(.horizontal, metrics.volumeHorizontalPadding)
                        .padding(.top, 1)
                        .focusable(true)
                        .digitalCrownRotation(
                            $crownVolume,
                            from: 0,
                            through: 1,
                            by: 0.05,
                            sensitivity: .medium,
                            isContinuous: true,
                            isHapticFeedbackEnabled: true
                        )
                    }
                    .frame(minHeight: geo.size.height)
                    .padding(.horizontal, 2)
                }
            }
            .background(
                Group {
                    if let url = audioManager.currentSong?.thumbnailURL {
                        WatchCachedImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            backgroundBase
                        }
                        .blur(radius: 30)
                        .opacity(0.35)
                        .ignoresSafeArea()
                    } else {
                        backgroundBase.ignoresSafeArea()
                    }
                }
            )
            .navigationTitle("Now Playing")
            .onAppear {
                crownVolume = audioManager.volume
                lastVolumeFeedbackStep = Int((crownVolume * 20).rounded())
            }
            .compatibleOnChange(of: crownVolume) { newValue in
                setVolume(newValue, feedback: true)
            }
            .compatibleOnChange(of: audioManager.volume) { newValue in
                if abs(newValue - crownVolume) > 0.01 {
                    crownVolume = newValue
                    lastVolumeFeedbackStep = Int((newValue * 20).rounded())
                }
            }
        } else {
            WatchEmptyState(
                systemImage: "music.note",
                title: "No Song Playing",
                message: "Choose a song from Home, Songs, or Search."
            )
            .navigationTitle("Now Playing")
        }
    }

    private var backgroundBase: Color {
        colorScheme == .dark
            ? Color.black
            : Color(red: 0.95, green: 0.96, blue: 0.99)
    }

    private var overlayColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.3)
            : Color.white.opacity(0.45)
    }

    private var progressAccessibilityValue: String {
        let remaining = max(0, audioManager.duration - audioManager.currentTime)
        guard audioManager.duration > 0 else {
            return audioManager.isLoading ? "Loading" : "0:00 elapsed"
        }
        return "\(formatTime(audioManager.currentTime)) elapsed, \(formatTime(remaining)) remaining"
    }

    private var queueAccessibilityValue: String {
        let count = audioManager.upNextSongs.count
        if count == 0 { return "No songs queued" }
        if count == 1 { return "1 song queued" }
        return "\(count) songs queued"
    }

    private func playerStateAccessibilityValue(for song: Song) -> String {
        if audioManager.isLoading {
            return "\(song.title), \(song.artistName), loading"
        }
        return "\(song.title), \(song.artistName), \(audioManager.isPlaying ? "playing" : "paused")"
    }

    private func formatTime(_ time: Double) -> String {
        if time.isNaN || time.isInfinite { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func togglePlayPause() {
        let wasPlaying = audioManager.isPlaying
        if audioManager.togglePlayPause() {
            WatchHaptic.play(wasPlaying ? .stop : .start)
        } else {
            WatchHaptic.play(.failure)
        }
    }

    private func seek(by seconds: Double) {
        guard audioManager.duration > 0 else {
            WatchHaptic.play(.failure)
            return
        }
        let target = min(audioManager.duration, max(0, audioManager.currentTime + seconds))
        audioManager.seek(to: target)
        WatchHaptic.play(seconds >= 0 ? .next : .previous)
    }

    private func setVolume(_ value: Double, feedback: Bool) {
        let clamped = min(max(value, 0), 1)
        audioManager.setVolume(clamped)
        if abs(clamped - crownVolume) > 0.001 {
            crownVolume = clamped
        }
        guard feedback else { return }
        let step = Int((clamped * 20).rounded())
        guard step != lastVolumeFeedbackStep else { return }
        lastVolumeFeedbackStep = step
        WatchHaptic.play(.click)
    }
}

private struct WatchPlayerIconButton: View {
    let systemName: String
    let diameter: CGFloat
    let iconSize: CGFloat
    let tint: Color
    let fill: Color
    var isDisabled = false
    let accessibilityLabel: String
    var accessibilityValue: String?
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: diameter, height: diameter)
                .overlay {
                    Image(systemName: systemName)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(tint)
                }
        }
        .buttonStyle(.watchPressable)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityHint(accessibilityHint ?? "")
    }
}

private struct WatchVolumeControl: View {
    let volume: Double
    let onAdjust: (Double) -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: volume < 0.05 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 16)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(Color.appAccent)
                        .frame(width: max(5, proxy.size.width * volume))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.11))
        .clipShape(Capsule())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: volume)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((volume * 100).rounded())) percent")
        .accessibilityHint("Turn the Digital Crown or swipe up and down to adjust.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onAdjust(volume + 0.05)
            case .decrement:
                onAdjust(volume - 0.05)
            @unknown default:
                break
            }
        }
    }
}
