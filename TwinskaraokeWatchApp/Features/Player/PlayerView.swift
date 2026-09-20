import SwiftUI

private struct WatchPlayerLayoutMetrics {
    let containerSize: CGSize
    let showsSecondaryRow: Bool
    static let topBarAllowance: CGFloat = 30
    static let pageIndicatorAllowance: CGFloat = 14

    private var compactWidth: Bool {
        containerSize.width < 180
    }

    private var compactHeight: Bool {
        containerSize.height < 180
    }
    var artworkSize: CGFloat {
        let rowsBelowArtwork: CGFloat = showsSecondaryRow ? 5 : 4
        let used = titleBlockHeight
            + statusRowHeight
            + primaryControlDiameter
            + (showsSecondaryRow ? secondaryControlSize : 0)
            + contentSpacing * rowsBelowArtwork
        let leftover = containerSize.height - used
        let ceiling = min(containerSize.width * (compactWidth ? 0.52 : 0.56), compactHeight ? 80 : 96)
        return min(max(leftover, 36), ceiling)
    }
    var titleBlockHeight: CGFloat {
        (titleSize + artistSize) * 1.2 + 2
    }
    var statusRowHeight: CGFloat {
        20
    }

    var contentSpacing: CGFloat {
        compactHeight ? 4 : 6
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
}

struct PlayerView: View {
    @Environment(AudioManager.self) var audioManager
    private let favorites = FavoritesManager.shared
    private let auth = WatchAuthManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var crownValue = 1.0
    @State private var crownTarget: CrownTarget = .volume
    @State private var lastCrownFeedbackStep: Int?
    @State private var lastScrubAt: Date?
    @State private var seatedCrownValue: Double?
    @State private var page: Page = .nowPlaying
    @State private var showsCrownReadout = false
    @State private var crownReadoutTimeout: Task<Void, Never>?
    enum CrownTarget {
        case volume
        case position
    }
    enum Page: Hashable {
        case nowPlaying
        case queue
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
            TabView(selection: $page) {
                nowPlayingPage(song: song)
                    .tag(Page.nowPlaying)
                if !audioManager.isRadioMode {
                    QueueView(showsCurrentSong: false)
                        .environment(audioManager)
                        .tag(Page.queue)
                }
            }
            .tabViewStyle(.page)
            .background(
                WatchPlayerBackground(song: audioManager.currentSong, base: backgroundBase)
            )
            .navigationTitle(page == .queue ? "Playing Next" : "")
            .onAppear {
                seatCrown(crownPosition(forVolume: audioManager.volume))
                lastCrownFeedbackStep = feedbackStep(crownValue)
                favorites.loadIfNeeded()
            }
            .onChange(of: crownValue) { _, newValue in
                guard isListenerTurn(newValue) else { return }
                applyCrown(newValue, feedback: true)
            }
            .onChange(of: audioManager.volume) { _, newValue in
                guard crownTarget == .volume else { return }
                let position = crownPosition(forVolume: newValue)
                if abs(position - crownValue) > 0.01 {
                    seatCrown(position)
                    lastCrownFeedbackStep = feedbackStep(position)
                }
            }
            .onChange(of: audioManager.currentTime) { _, _ in
                syncCrownToPlayback()
            }
            .onChange(of: audioManager.isRadioMode) { _, isRadio in
                guard isRadio else { return }
                if crownTarget == .position {
                    crownTarget = .volume
                    seatCrown(crownPosition(forVolume: audioManager.volume))
                }
                page = .nowPlaying
            }
        } else {
            WatchEmptyState(
                systemImage: "music.note",
                title: String(localized: "No Song Playing"),
                message: String(localized: "Choose a song from Home, Songs, or Search.")
            )
            .navigationTitle("Now Playing")
        }
    }
    private func nowPlayingPage(song: Song) -> some View {
        GeometryReader { geo in
            let metrics = WatchPlayerLayoutMetrics(
                containerSize: geo.size,
                showsSecondaryRow: !audioManager.isRadioMode
            )
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
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(song.artistName)
                        .font(.system(size: metrics.artistSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Now Playing")
                .accessibilityValue(playerStateAccessibilityValue(for: song))
                .accessibilityHint("Use the playback controls below.")
                if audioManager.isRadioMode {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 20)
                        .background(Capsule().fill(Color.appAccent.opacity(0.12)))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Live radio")
                } else {
                    Button(action: switchCrownTarget) {
                        VStack(spacing: 1) {
                            let total = max(audioManager.duration, 1)
                            ProgressView(value: min(audioManager.currentTime, total), total: total)
                                .tint(crownTarget == .position ? Color.appAccent : .secondary.opacity(0.8))
                                .scaleEffect(y: crownTarget == .position ? 1.0 : 0.6)
                            HStack {
                                Text(formatTime(audioManager.currentTime))
                                Spacer()
                                Text("-" + formatTime(max(0, audioManager.duration - audioManager.currentTime)))
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(crownTarget == .position ? Color.appAccent : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canScrub)
                    .padding(.horizontal, metrics.progressHorizontalPadding)
                    .animation(playbackAnimation, value: crownTarget)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Playback Position")
                    .accessibilityValue(progressAccessibilityValue)
                    .accessibilityHint(
                        canScrub
                            ? "Double tap to point the Digital Crown here. Swipe up or down to seek by 15 seconds."
                            : "Swipe up or down to seek by 15 seconds."
                    )
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
                Spacer(minLength: 0)

                HStack(spacing: metrics.mainControlSpacing) {
                    if !audioManager.isRadioMode {
                        WatchPlayerIconButton(
                            systemName: "backward.fill",
                            diameter: metrics.sideControlDiameter,
                            iconSize: metrics.sideControlIconSize,
                            tint: .primary,
                            fill: Color.secondary.opacity(0.14),
                            isDisabled: audioManager.isLoading,
                            accessibilityLabel: String(localized: "Previous Track"),
                            accessibilityValue: audioManager.isLoading ? String(localized: "Unavailable while loading") : nil,
                            accessibilityHint: String(localized: "Restarts the song or plays the previous track.")
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
                        accessibilityLabel: audioManager.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                        accessibilityValue: audioManager.isLoading ? String(localized: "Loading") : song.title,
                        accessibilityHint: audioManager.isPlaying ? String(localized: "Pauses \(song.title).") : String(localized: "Plays \(song.title).")
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
                            accessibilityLabel: String(localized: "Next Track"),
                            accessibilityValue: audioManager.isLoading ? String(localized: "Unavailable while loading") : nil,
                            accessibilityHint: String(localized: "Skips to the next track.")
                        ) {
                            audioManager.playNext()
                            WatchHaptic.play(.next)
                        }
                    }
                }
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
                                    .foregroundStyle(isFavorite ? Color.appAccent : .secondary)
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
                            .accessibilityValue(isFavorite ? String(localized: "On") : String(localized: "Off"))
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
                                .foregroundStyle(audioManager.isShuffleOn ? Color.appAccent : .secondary)
                                .frame(width: metrics.secondaryControlSize, height: metrics.secondaryControlSize)
                                .background(
                                    Circle().fill(audioManager.isShuffleOn ? Color.appAccent.opacity(0.14) : Color.clear)
                                )
                        }
                        .buttonStyle(.watchPressable)
                        .accessibilityLabel("Shuffle")
                        .accessibilityValue(audioManager.isShuffleOn ? String(localized: "On") : String(localized: "Off"))
                        .accessibilityHint(audioManager.isShuffleOn ? "Turns shuffle off." : "Turns shuffle on.")
                        Button {
                            audioManager.toggleMode()
                            WatchHaptic.play(.click)
                        } label: {
                            Image(systemName: audioManager.playbackMode.iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    audioManager.playbackMode == .singleLoop ? Color.appAccent : .secondary
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
                        Button {
                            page = .queue
                            WatchHaptic.play(.click)
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: metrics.secondaryControlSize, height: metrics.secondaryControlSize)
                        }
                        .buttonStyle(.watchPressable)
                        .accessibilityLabel("Playing Next")
                        .accessibilityValue(queueAccessibilityValue)
                        .accessibilityHint("Show the queue for \(song.title)")
                        .accessibilityIdentifier("WatchPlayer.queue")
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .padding(.horizontal, 2)
        }
        .overlay(alignment: .top) {
            WatchCrownReadout(target: crownTarget, valueText: crownValueText)
                .padding(.top, 8)
                .opacity(showsCrownReadout ? 1 : 0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.15),
                    value: showsCrownReadout
                )
                .allowsHitTesting(false)
        }
        .padding(.top, WatchPlayerLayoutMetrics.topBarAllowance)
        .padding(.bottom, WatchPlayerLayoutMetrics.pageIndicatorAllowance)
        .ignoresSafeArea(edges: [.top, .bottom])
        .focusable(true)
        .digitalCrownRotation(
            detent: $crownValue,
            from: 0,
            through: 1,
            by: crownTarget == .volume ? 0.05 : 0.01,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true,
            onChange: { _ in showCrownReadout() },
            onIdle: { hideCrownReadoutAfterGrace() }
        )
        .onDisappear {
            crownReadoutTimeout?.cancel()
            showsCrownReadout = false
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
            return audioManager.isLoading ? String(localized: "Loading") : String(localized: "0:00 elapsed")
        }
        return String(localized: "\(formatTime(audioManager.currentTime)) elapsed, \(formatTime(remaining)) remaining")
    }

    private var queueAccessibilityValue: String {
        let count = audioManager.upNextSongs.count
        if count == 0 { return String(localized: "No songs queued") }
        if count == 1 { return String(localized: "1 song queued") }
        return String(localized: "\(count) songs queued")
    }

    private func playerStateAccessibilityValue(for song: Song) -> String {
        if audioManager.isLoading {
            return String(localized: "\(song.title), \(song.artistName), loading")
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
    private var canScrub: Bool {
        !audioManager.isRadioMode && audioManager.duration > 0
    }

    private var crownValueText: String {
        switch crownTarget {
        case .volume:
            "\(Int((volume(forCrownPosition: crownValue) * 100).rounded()))%"
        case .position:
            formatTime(crownValue * audioManager.duration)
        }
    }

    private func crownPosition(forVolume volume: Double) -> Double {
        WatchCrownVolume.position(forVolume: volume)
    }

    private func volume(forCrownPosition position: Double) -> Double {
        WatchCrownVolume.volume(forPosition: position)
    }
    private func feedbackStep(_ crownPosition: Double) -> Int {
        Int((crownPosition * 20).rounded())
    }
    private func seatCrown(_ value: Double) {
        seatedCrownValue = value
        crownValue = value
    }
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
        lastCrownFeedbackStep = nil
        switch crownTarget {
        case .volume:
            seatCrown(crownPosition(forVolume: audioManager.volume))
            lastCrownFeedbackStep = feedbackStep(crownValue)
        case .position:
            seatCrown(playbackFraction)
            lastScrubAt = nil
        }
        showCrownReadout()
        hideCrownReadoutAfterGrace()
        WatchHaptic.play(.click)
    }

    private var playbackFraction: Double {
        guard audioManager.duration > 0 else { return 0 }
        return min(max(audioManager.currentTime / audioManager.duration, 0), 1)
    }
    private static let crownReadoutGrace: Duration = .seconds(1.2)
    private func showCrownReadout() {
        crownReadoutTimeout?.cancel()
        crownReadoutTimeout = nil
        guard !showsCrownReadout else { return }
        showsCrownReadout = true
    }

    private func hideCrownReadoutAfterGrace() {
        crownReadoutTimeout?.cancel()
        crownReadoutTimeout = Task { @MainActor in
            try? await Task.sleep(for: Self.crownReadoutGrace)
            guard !Task.isCancelled else { return }
            showsCrownReadout = false
        }
    }

    private func applyCrown(_ value: Double, feedback: Bool) {
        showCrownReadout()
        hideCrownReadoutAfterGrace()
        switch crownTarget {
        case .volume:
            setVolume(fromCrown: value, feedback: feedback)
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
        let step = feedbackStep(clamped)
        guard step != lastCrownFeedbackStep else { return }
        lastCrownFeedbackStep = step
        WatchHaptic.play(.click)
    }
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

    private func setVolume(fromCrown position: Double, feedback: Bool) {
        let clamped = min(max(position, 0), 1)
        audioManager.setVolume(volume(forCrownPosition: clamped))
        if abs(clamped - crownValue) > 0.001 {
            seatCrown(clamped)
        }
        guard feedback else { return }
        let step = feedbackStep(clamped)
        guard step != lastCrownFeedbackStep else { return }
        lastCrownFeedbackStep = step
        WatchHaptic.play(.click)
    }
}
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
                        .foregroundStyle(tint)
                }
        }
        .buttonStyle(.watchPressable)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityHint(accessibilityHint ?? "")
    }
}
private struct WatchCrownReadout: View {
    let target: PlayerView.CrownTarget
    let valueText: String

    var body: some View {
        Label(valueText, systemImage: target == .volume ? "speaker.wave.2.fill" : "timeline.selection")
            .font(.system(size: 12, weight: .semibold, design: target == .volume ? .default : .monospaced))
            .foregroundStyle(target == .position ? Color.appAccent : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.78)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(target == .volume ? "Volume" : "Playback Position")
            .accessibilityValue(valueText)
            .accessibilityIdentifier("WatchPlayer.crownReadout")
    }
}
