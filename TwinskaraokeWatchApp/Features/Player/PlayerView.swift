import SwiftUI

private struct WatchPlayerLayoutMetrics {
    let containerSize: CGSize
    /// Radio drops the secondary row, which changes how much height is left
    /// over for the artwork.
    let showsSecondaryRow: Bool

    /// watchOS hands a paged TabView a page inset by about 62pt at the top and
    /// 36pt at the bottom — 40% of a 46mm screen. Left alone it squeezed the
    /// artwork onto its 36pt floor and stranded the transport mid-screen, so
    /// the page takes that room back and reserves only what is spoken for: the
    /// clock above, the paging dots below.
    static let topBarAllowance: CGFloat = 30
    static let pageIndicatorAllowance: CGFloat = 14

    private var compactWidth: Bool {
        containerSize.width < 180
    }

    private var compactHeight: Bool {
        containerSize.height < 180
    }

    /// Every row below the artwork has a height we can name, so the artwork
    /// takes whatever is left rather than a fixed fraction of the screen.
    /// That is what lets the page fit a 42mm watch without scrolling, and
    /// without shrinking the controls people actually have to hit.
    var artworkSize: CGFloat {
        // Six children with the secondary row, five without — and the flexible
        // spacer above the transport counts as one of them.
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

    /// Title over artist, at their rendered line heights.
    var titleBlockHeight: CGFloat {
        (titleSize + artistSize) * 1.2 + 2
    }

    /// The progress bar with the elapsed/remaining pair under it — or, on
    /// radio, the "Live" capsule that stands in for both.
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
    @State private var page: Page = .nowPlaying
    /// Whether the Crown's readout is on screen.
    ///
    /// It is worth a corner of the display while the listener is turning and
    /// nothing at all when they are not.
    @State private var showsCrownReadout = false
    @State private var crownReadoutTimeout: Task<Void, Never>?

    /// What the Digital Crown drives. A watch has one precise input and two
    /// things worth pointing it at, so it is switched rather than split.
    enum CrownTarget {
        case volume
        case position
    }

    /// The player and its queue sit side by side rather than stacked in the
    /// navigation stack, so the queue is one swipe left instead of a push.
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

                // The station picks what plays next, so there is no queue to
                // swipe to while the radio is on.
                if !audioManager.isRadioMode {
                    QueueView(showsCurrentSong: false)
                        .environmentObject(audioManager)
                        .tag(Page.queue)
                }
            }
            .tabViewStyle(.page)
            .background(
                WatchPlayerBackground(song: audioManager.currentSong, base: backgroundBase)
            )
            // The player page carries no title: watchOS draws one over the page
            // rather than above it, so "Now Playing" landed on top of the
            // artwork — and the song's own title sits right under it anyway.
            .navigationTitle(page == .queue ? "Playing Next" : "")
            .onAppear {
                seatCrown(crownPosition(forVolume: audioManager.volume))
                lastCrownFeedbackStep = feedbackStep(crownValue)
                favorites.loadIfNeeded()
            }
            .compatibleOnChange(of: crownValue) { newValue in
                guard isListenerTurn(newValue) else { return }
                applyCrown(newValue, feedback: true)
            }
            .compatibleOnChange(of: audioManager.volume) { newValue in
                guard crownTarget == .volume else { return }
                let position = crownPosition(forVolume: newValue)
                if abs(position - crownValue) > 0.01 {
                    seatCrown(position)
                    lastCrownFeedbackStep = feedbackStep(position)
                }
            }
            .compatibleOnChange(of: audioManager.currentTime) { _ in
                syncCrownToPlayback()
            }
            .compatibleOnChange(of: audioManager.isRadioMode) { isRadio in
                guard isRadio else { return }
                // A live stream has no position for the Crown to point at, and
                // the queue page it may be sitting on no longer exists.
                if crownTarget == .position {
                    crownTarget = .volume
                    seatCrown(crownPosition(forVolume: audioManager.volume))
                }
                page = .nowPlaying
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

    /// The player itself: one screenful, sized to fit rather than scroll.
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
                    // Doubles as the Crown's target switch: the bar is
                    // the thing being scrubbed, so it is also the thing
                    // you tap to point the Crown at it.
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
                            .foregroundColor(crownTarget == .position ? .appAccent : .secondary)
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

                // Anything the artwork's ceiling left over lands here, so the
                // surplus on a large watch pushes the transport down to the
                // bottom edge instead of padding every gap a little.
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
                        // The queue is a swipe away rather than a push,
                        // but VoiceOver has no swipe to give it, so it
                        // keeps a button of its own.
                        Button {
                            page = .queue
                            WatchHaptic.play(.click)
                        } label: {
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
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .padding(.horizontal, 2)
        }
        // Drawn here rather than handed to `digitalCrownAccessory`: the system
        // accessory re-presents itself every time the page re-renders, and this
        // page re-renders twice a second to move the progress bar, so the
        // readout blinked its way through songs nobody was adjusting. It rides
        // over the artwork, which is the one thing on the page that can be
        // covered for a second without costing the listener anything.
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
        // The overload that reports rotation as well as value: `onChange` fires
        // on the turn itself, so it still speaks at either end of the range
        // where the value has nowhere left to go.
        .digitalCrownRotation(
            detent: $crownValue,
            from: 0,
            through: 1,
            by: crownTarget == .volume ? 0.05 : 0.01,
            sensitivity: .medium,
            // Never wrap: rolling past the end of a track back
            // to its start is not something anyone means to do.
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

    /// The Crown maps straight onto volume: forward is louder, the way it runs
    /// everywhere else on the watch.
    ///
    /// Measured rather than assumed, twice, against a freshly installed app
    /// sitting at its default 100%: rolling backward drove the stored volume
    /// to 0, and rolling forward moved it not at all — it was already against
    /// the stop. Both are the right way round, so the direction is pinned here
    /// and by `testWatchPlayerCrownRolledForwardRaisesVolume` rather than
    /// flipped on how it feels. What was missing was any sign of the stop:
    /// forward at 100% did nothing and said nothing, which reads exactly like
    /// a Crown wired backwards. The readout now answers there.
    private func crownPosition(forVolume volume: Double) -> Double {
        volume
    }

    /// One haptic tick per 5% of a turn, counted in Crown positions so both
    /// targets share the same scale.
    private func feedbackStep(_ crownPosition: Double) -> Int {
        Int((crownPosition * 20).rounded())
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
            seatCrown(crownPosition(forVolume: audioManager.volume))
            lastCrownFeedbackStep = feedbackStep(crownValue)
        case .position:
            seatCrown(playbackFraction)
            lastScrubAt = nil
        }
        // Switching targets is worth showing: the readout is what says which
        // of the two the Crown is now pointed at.
        showCrownReadout()
        hideCrownReadoutAfterGrace()
        WatchHaptic.play(.click)
    }

    private var playbackFraction: Double {
        guard audioManager.duration > 0 else { return 0 }
        return min(max(audioManager.currentTime / audioManager.duration, 0), 1)
    }

    /// How long the readout stays up after the Crown stops moving.
    private static let crownReadoutGrace: Duration = .seconds(1.2)

    /// Puts the readout up while the Crown is in use.
    ///
    /// Driven by the Crown's own rotation events rather than by the value
    /// changing, because the value stops changing at either end of the range:
    /// a readout keyed to the value went blank exactly when you rolled into
    /// the top, which is what made a track already at 100% feel like the
    /// Crown was dead in that direction.
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

    private func setVolume(fromCrown position: Double, feedback: Bool) {
        let clamped = min(max(position, 0), 1)
        audioManager.setVolume(clamped)
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

/// What the Crown is pointed at, drawn over the player while it is being
/// turned. It costs no room in the layout — it is only ever on screen for the
/// moment it is being read, so it sits over the artwork rather than pushing it.
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
