import SwiftUI
import WatchKit

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
    static let topBarAllowance: CGFloat = 44
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
        let ceiling = min(containerSize.width * (compactWidth ? 0.60 : 0.65), compactHeight ? 92 : 110)
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
        compactHeight ? 3 : 4
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
        compactWidth ? 8 : 12
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
    @State private var scrubPosition: Double?
    @State private var page: Page = .nowPlaying

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

    @State private var showOutputOptions = false
    @State private var showSongOptions = false

    var body: some View {
        if let song = audioManager.currentSong {
            TabView(selection: $page) {
                nowPlayingPage(song: song)
                    .tag(Page.nowPlaying)

                // The station picks what plays next, so there is no queue to
                // swipe to while the radio is on.
                if !audioManager.isRadioMode {
                    QueueView(showsCurrentSong: false)
                        .environment(audioManager)
                        .tag(Page.queue)
                }
            }
            .tabViewStyle(.page)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showOutputOptions = true } label: {
                        Image(systemName: "airplay.audio")
                    }
                    .accessibilityLabel("Audio Output")
                }
            }
            .sheet(isPresented: $showOutputOptions) {
                NowPlayingView()
            }
            .sheet(isPresented: $showSongOptions) {
                NavigationStack {
                    List {
                        if !audioManager.isRadioMode {
                            WatchDownloadMenu(song: song)
                            if auth.linkState == .signedIn {
                                Button(favorites.isFavorite(song.id) ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") {
                                    favorites.toggle(songID: song.id)
                                }
                            }
                        }
                        NavigationLink {
                            WatchSleepTimerView().environment(audioManager)
                        } label: {
                            Label("Sleep Timer", systemImage: "moon.zzz")
                        }
                    }
                    .navigationTitle("Options")
                }
            }
            .background(
                WatchPlayerBackground(song: audioManager.currentSong, base: backgroundBase)
            )
            // The player page carries no title: watchOS draws one over the page
            // rather than above it, so "Now Playing" landed on top of the
            // artwork — and the song's own title sits right under it anyway.
            .navigationTitle(page == .queue ? "Playing Next" : "")
            .accessibilityAction(named: Text("Playing Next")) { page = .queue }
            .onAppear { favorites.loadIfNeeded() }
            .onChange(of: audioManager.isRadioMode) { _, isRadio in
                if isRadio { page = .nowPlaying }
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
                        image.resizable().scaledToFill()
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
                    // A live stream has no duration to fill a bar with
                    // and nowhere to seek to.
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 20)
                        .background(Capsule().fill(Color.appAccent.opacity(0.12)))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Live radio")
                } else {
                    GeometryReader { geometry in
                        let position = scrubPosition ?? audioManager.currentTime
                        VStack(spacing: 1) {
                            ProgressView(value: min(position, max(audioManager.duration, 1)), total: max(audioManager.duration, 1))
                                .tint(.secondary.opacity(0.8))
                                .scaleEffect(y: 0.6)
                            HStack {
                                Text(formatTime(position))
                                Spacer()
                                Text("-" + formatTime(max(0, audioManager.duration - position)))
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                        .frame(height: metrics.statusRowHeight)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard canScrub else { return }
                                scrubPosition = WatchPlaybackPosition.time(at: value.location.x,
                                    width: geometry.size.width, duration: audioManager.duration)
                            }
                            .onEnded { _ in
                                if let scrubPosition { audioManager.seek(to: scrubPosition) }
                                scrubPosition = nil
                            })
                    }
                    .frame(height: metrics.statusRowHeight)
                    .padding(.horizontal, metrics.progressHorizontalPadding)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Playback Position")
                    .accessibilityValue(progressAccessibilityValue)
                    .accessibilityIdentifier("WatchPlayer.position")
                    .accessibilityHint("Tap or drag to seek. Swipe up or down to seek by 15 seconds.")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: seek(by: 15)
                        case .decrement: seek(by: -15)
                        @unknown default: break
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
                                    audioManager.playbackMode.isActive ? Color.appAccent : .secondary
                                )
                                .frame(width: metrics.secondaryControlSize, height: metrics.secondaryControlSize)
                                .background(
                                    Circle().fill(
                                        audioManager.playbackMode.isActive
                                            ? Color.appAccent.opacity(0.14) : Color.clear
                                    )
                                )
                        }
                        .buttonStyle(.watchPressable)
                        .accessibilityLabel("Repeat")
                        .accessibilityValue(
                            audioManager.playbackMode.accessibilityValue
                        )
                        .accessibilityHint("Cycles repeat mode.")
                        // Queue navigation remains on the adjacent page.
                        Button {
                            showSongOptions = true
                            WatchHaptic.play(.click)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: metrics.secondaryControlSize, height: metrics.secondaryControlSize)
                        }
                        .buttonStyle(.watchPressable)
                        .accessibilityLabel("Options")
                        .accessibilityHint("Download, favorites, and sleep timer")
                        .accessibilityIdentifier("WatchPlayer.options")

                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .padding(.horizontal, 2)
        }
        // Preserve Crown routing without another visible playback control.
        .background {
            systemVolumeControl
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.top, WatchPlayerLayoutMetrics.topBarAllowance)
        .padding(.bottom, WatchPlayerLayoutMetrics.pageIndicatorAllowance)
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    private var systemVolumeControl: some View {
        WatchSystemVolumeControl(owner: WatchAuthManager.shared.output,
            isFocused: page == .nowPlaying && !showOutputOptions && !showSongOptions)
            .id(WatchAuthManager.shared.output)
            .frame(width: 40, height: 40)
            .scaleEffect(0.65)
            .accessibilityLabel("Volume")
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

    /// Touch seeking needs a known track length; live radio cannot seek.
    private var canScrub: Bool {
        !audioManager.isRadioMode && audioManager.duration > 0
    }

}

nonisolated enum WatchPlaybackPosition {
    static func time(at x: Double, width: Double, duration: Double) -> Double {
        guard x.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return 0 }
        return min(max(x / width, 0), 1) * duration
    }
}

private struct WatchSystemVolumeControl: WKInterfaceObjectRepresentable {
    let owner: CompanionPlayback.Owner
    let isFocused: Bool

    func makeWKInterfaceObject(context: Context) -> WKInterfaceVolumeControl {
        WKInterfaceVolumeControl(origin: owner == .watch ? .local : .companion)
    }

    final class Coordinator { var focused: Bool? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateWKInterfaceObject(_ control: WKInterfaceVolumeControl, context: Context) {
        guard context.coordinator.focused != isFocused else { return }
        context.coordinator.focused = isFocused
        if isFocused { control.focus() } else { control.resignFocus() }
    }

    static func dismantleWKInterfaceObject(_ control: WKInterfaceVolumeControl, coordinator: Coordinator) {
        control.resignFocus()
    }
}

private struct WatchSleepTimerView: View {
    @Environment(AudioManager.self) private var audio
    @State private var selectionRevision = 0

    var body: some View {
        ScrollViewReader { proxy in
            List {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    if let deadline = audio.sleepTimer.deadline {
                        let remaining = max(0, Int(deadline.timeIntervalSince(timeline.date).rounded(.up)))
                        Text("\(remaining / 60):\(String(format: "%02d", remaining % 60)) remaining")
                            .monospacedDigit()
                    } else if audio.sleepTimer.endsWithCurrentSong {
                        Text("End of song")
                    } else {
                        Text("Sleep timer off").foregroundStyle(.secondary)
                    }
                }
                .id("timerStatus")
                .accessibilityIdentifier("WatchPlayer.sleepStatus")
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { select { audio.setSleepTimer(minutes: minutes) } }
                }
                if !audio.isRadioMode {
                    Button("When Current Song Ends") { select { audio.setSleepTimer(endOfSong: true) } }
                }
                if audio.sleepTimer.isActive {
                    Button("Cancel Sleep Timer", role: .destructive) { select { audio.setSleepTimer() } }
                }
            }
            .onChange(of: selectionRevision) { _, _ in proxy.scrollTo("timerStatus", anchor: .top) }
            .onChange(of: audio.sleepTimer.deadline) { _, _ in proxy.scrollTo("timerStatus", anchor: .top) }
            .onChange(of: audio.sleepTimer.endsWithCurrentSong) { _, _ in proxy.scrollTo("timerStatus", anchor: .top) }
        }
        .navigationTitle("Sleep Timer")
    }

    private func select(_ action: () -> Void) {
        action()
        selectionRevision += 1
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
