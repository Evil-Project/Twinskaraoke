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
    @ObservedObject private var favorites = FavoritesManager.shared
    @ObservedObject private var auth = WatchAuthManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var crownValue = 1.0
    @State private var crownTarget: CrownTarget = .volume
    @State private var lastCrownFeedbackStep: Int?
    /// Set while the listener is turning the Crown to scrub, so the periodic
    /// playback tick doesn't yank the handle back out from under them.
    @State private var lastScrubAt: Date?
    /// The value of the last *programmatic* `crownValue` assignment.
    ///
    /// `digitalCrownRotation` and our own re-seating both write the same state,
    /// and `onChange` cannot tell them apart. Without this, following playback
    /// in scrub mode would seek the player to its own position on every tick,
    /// and switching targets would fire a spurious adjustment.
    @State private var seatedCrownValue: Double?

    /// What the Digital Crown drives. A watch has one precise input and two
    /// things worth pointing it at, so it is switched rather than split.
    enum CrownTarget {
        case volume
        case position
    }

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
                        if audioManager.isRadioMode {
                            // A live stream has no duration to fill a bar with
                            // and nowhere to seek to.
                            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.appAccent)
                                .padding(.horizontal, 8)
                                .frame(minHeight: 20)
                                .background(Capsule().fill(Color.appAccent.opacity(0.12)))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Live radio")
                        } else {
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
                        }

                        HStack(spacing: metrics.mainControlSpacing) {
                            if !audioManager.isRadioMode {
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

                            if !audioManager.isRadioMode {
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
                        }

                        // Shuffle, repeat, the queue and starring are all
                        // library concepts; the station decides what plays.
                        if !audioManager.isRadioMode {
                            HStack(spacing: metrics.secondaryControlSpacing) {
                                if auth.linkState == .signedIn {
                                    let isFavorite = favorites.isFavorite(song.id)
                                    Button {
                                        favorites.toggle(songID: song.id)
                                        WatchHaptic.play(isFavorite ? .click : .success)
                                    } label: {
                                        Image(systemName: isFavorite ? "star.fill" : "star")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(isFavorite ? .appAccent : .secondary)
                                            .frame(
                                                width: metrics.secondaryControlSize,
                                                height: metrics.secondaryControlSize
                                            )
                                            .background(
                                                Circle().fill(
                                                    isFavorite ? Color.appAccent.opacity(0.14) : Color.clear
                                                )
                                            )
                                    }
                                    .buttonStyle(.watchPressable)
                                    .accessibilityLabel("Favorite")
                                    .accessibilityValue(isFavorite ? "On" : "Off")
                                    .accessibilityHint(
                                        isFavorite
                                            ? "Removes \(song.title) from your favorites."
                                            : "Adds \(song.title) to your favorites."
                                    )
                                }
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
                        }

                        WatchCrownControl(
                            target: crownTarget,
                            fraction: crownValue,
                            valueText: crownValueText,
                            canSwitchTarget: canScrub,
                            onAdjust: { applyCrown($0, feedback: true) },
                            onSwitchTarget: switchCrownTarget
                        )
                        .padding(.horizontal, metrics.volumeHorizontalPadding)
                        .padding(.top, 1)
                        .focusable(true)
                        .digitalCrownRotation(
                            $crownValue,
                            from: 0,
                            through: 1,
                            by: crownTarget == .volume ? 0.05 : 0.01,
                            sensitivity: .medium,
                            // Never wrap: rolling past the end of a track back
                            // to its start is not something anyone means to do.
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )
                    }
                    .frame(minHeight: geo.size.height)
                    .padding(.horizontal, 2)
                }
            }
            .background(
                WatchPlayerBackground(song: audioManager.currentSong, base: backgroundBase)
            )
            .navigationTitle("Now Playing")
            .onAppear {
                seatCrown(audioManager.volume)
                lastCrownFeedbackStep = Int((crownValue * 20).rounded())
                favorites.loadIfNeeded()
            }
            .compatibleOnChange(of: crownValue) { newValue in
                guard isListenerTurn(newValue) else { return }
                applyCrown(newValue, feedback: true)
            }
            .compatibleOnChange(of: audioManager.volume) { newValue in
                guard crownTarget == .volume else { return }
                if abs(newValue - crownValue) > 0.01 {
                    seatCrown(newValue)
                    lastCrownFeedbackStep = Int((newValue * 20).rounded())
                }
            }
            .compatibleOnChange(of: audioManager.currentTime) { _ in
                syncCrownToPlayback()
            }
            .compatibleOnChange(of: audioManager.isRadioMode) { isRadio in
                // A live stream has no position, so the Crown has nowhere else
                // to point.
                if isRadio, crownTarget == .position {
                    crownTarget = .volume
                    seatCrown(audioManager.volume)
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

    /// Scrubbing needs a known length to map the Crown onto, which rules out
    /// live radio and a track whose duration hasn't resolved yet.
    private var canScrub: Bool {
        !audioManager.isRadioMode && audioManager.duration > 0
    }

    private var crownValueText: String {
        switch crownTarget {
        case .volume:
            "\(Int((crownValue * 100).rounded()))%"
        case .position:
            formatTime(crownValue * audioManager.duration)
        }
    }

    /// Marks a programmatic write so `onChange` can ignore the echo.
    private func seatCrown(_ value: Double) {
        seatedCrownValue = value
        crownValue = value
    }

    /// True when `crownValue` moved because the listener turned the Crown,
    /// rather than because we re-seated it.
    private func isListenerTurn(_ value: Double) -> Bool {
        defer { seatedCrownValue = nil }
        guard let seatedCrownValue else { return true }
        return abs(value - seatedCrownValue) > 0.0005
    }

    private func switchCrownTarget() {
        guard canScrub else {
            WatchHaptic.play(.failure)
            return
        }
        crownTarget = crownTarget == .volume ? .position : .volume
        // Re-seat the handle on whatever it now controls. The feedback step is
        // reset too: it is shared between both targets, and a stale value would
        // swallow the first tick after the switch.
        lastCrownFeedbackStep = nil
        switch crownTarget {
        case .volume:
            seatCrown(audioManager.volume)
            lastCrownFeedbackStep = Int((crownValue * 20).rounded())
        case .position:
            seatCrown(playbackFraction)
            lastScrubAt = nil
        }
        WatchHaptic.play(.click)
    }

    private var playbackFraction: Double {
        guard audioManager.duration > 0 else { return 0 }
        return min(max(audioManager.currentTime / audioManager.duration, 0), 1)
    }

    private func applyCrown(_ value: Double, feedback: Bool) {
        switch crownTarget {
        case .volume:
            setVolume(value, feedback: feedback)
        case .position:
            scrub(to: value, feedback: feedback)
        }
    }

    private func scrub(to fraction: Double, feedback: Bool) {
        guard canScrub else { return }
        let clamped = min(max(fraction, 0), 1)
        lastScrubAt = Date()
        audioManager.seek(to: clamped * audioManager.duration)
        guard feedback else { return }
        // One tick per 5% keeps the haptics from buzzing continuously through
        // a slow turn.
        let step = Int((clamped * 20).rounded())
        guard step != lastCrownFeedbackStep else { return }
        lastCrownFeedbackStep = step
        WatchHaptic.play(.click)
    }

    /// Follows playback while the Crown is idle, so the handle keeps up with
    /// the track without fighting an in-progress scrub.
    private func syncCrownToPlayback() {
        guard crownTarget == .position, canScrub else { return }
        if let lastScrubAt, Date().timeIntervalSince(lastScrubAt) < 1.5 {
            return
        }
        let fraction = playbackFraction
        if abs(fraction - crownValue) > 0.01 {
            seatCrown(fraction)
        }
    }

    private func setVolume(_ value: Double, feedback: Bool) {
        let clamped = min(max(value, 0), 1)
        audioManager.setVolume(clamped)
        if abs(clamped - crownValue) > 0.001 {
            seatCrown(clamped)
        }
        guard feedback else { return }
        let step = Int((clamped * 20).rounded())
        guard step != lastCrownFeedbackStep else { return }
        lastCrownFeedbackStep = step
        WatchHaptic.play(.click)
    }
}

/// Full-screen blurred backdrop. Uses the tiny server-side blurred artwork variant
/// (32px, upscaled) instead of an on-device .blur to avoid continuous GPU cost.
private struct WatchPlayerBackground: View {
    let song: Song?
    let base: Color

    private var blurURL: URL? {
        guard let url = song?.thumbnailURL else { return nil }
        return ArtworkURLBuilder.variantURL(from: url, variant: .blur)
    }

    var body: some View {
        Group {
            if let url = blurURL {
                WatchCachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    base
                }
                .opacity(0.35)
                .ignoresSafeArea()
            } else {
                base.ignoresSafeArea()
            }
        }
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

/// The Digital Crown's readout: a filled track showing whatever the Crown is
/// currently pointed at, and a tap target to point it at the other thing.
private struct WatchCrownControl: View {
    let target: PlayerView.CrownTarget
    let fraction: Double
    let valueText: String
    let canSwitchTarget: Bool
    let onAdjust: (Double) -> Void
    let onSwitchTarget: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var iconName: String {
        switch target {
        case .volume:
            fraction < 0.05 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .position:
            "timeline.selection"
        }
    }

    private var label: String {
        target == .volume ? "Volume" : "Playback Position"
    }

    private var step: Double {
        target == .volume ? 0.05 : 0.02
    }

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onSwitchTarget) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(target == .position ? .appAccent : .secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .disabled(!canSwitchTarget)
            .accessibilityLabel("Crown Controls")
            .accessibilityValue(label)
            .accessibilityHint(
                canSwitchTarget
                    ? "Switches the Digital Crown between volume and playback position."
                    : "Playback position is unavailable for this track."
            )

            // The track carries the slider semantics as a leaf of its own. The
            // switch button beside it is a separate element, so an adjustable
            // action never sits on a node that also exposes children.
            HStack(spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.14))
                        Capsule()
                            .fill(Color.appAccent)
                            .frame(width: max(5, proxy.size.width * fraction))
                    }
                }
                .frame(height: 5)

                if target == .position {
                    Text(valueText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(valueText)
            .accessibilityHint("Turn the Digital Crown or swipe up and down to adjust.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onAdjust(fraction + step)
                case .decrement:
                    onAdjust(fraction - step)
                @unknown default:
                    break
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.11))
        .clipShape(Capsule())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: fraction)
    }
}
