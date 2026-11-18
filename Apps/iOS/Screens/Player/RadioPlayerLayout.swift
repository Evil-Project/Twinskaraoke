import SwiftUI

struct RadioPlayerLayout: View {
    @Environment(AudioPlayerManager.self) var audioManager
    let favorites: FavoritesManager
    private let radio = RadioController.shared
    /// Only to stop the marquees while this layout is parked below the screen —
    /// the player stays mounted when it is closed, so nothing else would.
    private let presentation = NowPlayingPresentation.shared
    @Environment(\.appReduceMotion) private var reduceMotion
    @Binding var showingQueue: Bool
    let song: Song
    let metrics: PlayerLayoutMetrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let style = RadioPlayerLayoutStyle(
            usesPadLayout: metrics.usesPadLayout,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        switch style.arrangement {
        case .compact: compactLayout
        case .wide: wideLayout
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            artwork(size: RadioPlayerLayoutStyle.artworkSize(for: .compact, metrics: metrics))
            Spacer(minLength: 28)
            headerRow
                .padding(.horizontal, 32)
            Spacer(minLength: 10)
            playStopButton
            Spacer(minLength: 24)
            PlayerVolumeRow()
            toolbar
            Spacer(minLength: 8)
        }
    }

    /// The music player's lyrics-off iPad layout (`padArtworkLayout`) with the
    /// radio's controls: the same artwork size, column width and paddings, so
    /// switching between a song and the station doesn't resize the canvas.
    private var wideLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            artwork(size: RadioPlayerLayoutStyle.artworkSize(for: .wide, metrics: metrics))
            headerRow
                .padding(.top, 26)
            Spacer(minLength: 18)
            playStopButton
            PlayerVolumeRow(horizontalPadding: 0)
                .padding(.top, metrics.padVolumeTopPadding)
            toolbar
        }
        .padding(.top, metrics.padTopInset)
        .frame(maxWidth: metrics.padArtworkContentMaxWidth, maxHeight: .infinity)
        .padding(.horizontal, metrics.padOuterPadding)
        .frame(maxWidth: .infinity)
    }

    private func artwork(size: CGFloat) -> some View {
        PlayerArtworkView(song: song, size: size)
            .contextMenu {
                radioActions
            } preview: {
                SongContextPreview(song: song)
            }
    }

    /// Pads itself to nothing in radio mode, so one call fits both layouts.
    private var toolbar: some View {
        PlayerBottomToolbar(
            showingQueue: $showingQueue,
            song: song,
            onLyricsToggle: {},
            showLyrics: false
        )
    }

    /// At an accessibility size the live line moves above the title row and
    /// takes the row's full width; beside the title buttons it only had a
    /// third of the screen, where "LIVE RADIO" truncated or, wrapped, pushed
    /// the toolbar off the bottom.
    private var headerRow: some View {
        let liftsLiveMeta = RadioPlayerLayoutStyle.stacksLiveMeta(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        return VStack(alignment: .leading, spacing: AM.Spacing.xs) {
            if liftsLiveMeta {
                liveMeta
                    .accessibilityElement(children: .combine)
            }
            titleRow(includesLiveMeta: !liftsLiveMeta)
        }
        .contextMenu {
            radioActions
        } preview: {
            SongContextPreview(song: song)
        }
    }

    private var liveMeta: some View {
        RadioLiveMeta(
            listeners: radio.nowPlaying?.listeners?.unique,
            isPlaying: audioManager.isPlaying,
            isPaused: !presentation.isExpanded
        )
    }

    private func titleRow(includesLiveMeta: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if includesLiveMeta {
                    liveMeta
                }
                MarqueeText(
                    text: song.title,
                    font: AM.Font.nowPlayingTitle,
                    color: .primary,
                    isPaused: !presentation.isExpanded
                )
                MarqueeText(
                    text: song.displayArtist,
                    font: AM.Font.nowPlayingArtist,
                    color: .secondary,
                    isPaused: !presentation.isExpanded
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Live radio")
            .accessibilityValue("\(song.title), \(song.displayArtist)")
            // Not a `Spacer`. The title has been flexible ever since it became a
            // marquee, and a `Spacer` is flexible too, so the two were quietly
            // splitting the free width — the title scrolled from about half the
            // row while the other half sat empty.
            .padding(.trailing, 8)
            // The music player's order and chrome: favourite, then More.
            // A station ident or jingle has no catalogue id, so there is no
            // favourite to offer. Signed out, the shared button dims instead.
            if let songID = radioFavoriteID {
                PlayerFavoriteButton(song: song, favoriteID: songID, font: .title2)
            }
            PlayerTitleMenu(song: song) {
                SleepTimerMenu()
            }
        }
    }

    private var playStopButton: some View {
        Button {
            audioManager.togglePlayPause()
        } label: {
            Group {
                if !reduceMotion {
                    Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
                }
            }
            .font(.largeTitle.bold())
            .foregroundStyle(.primary)
            .frame(width: 88, height: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.6, haptic: .commit))
        .accessibilityLabel(audioManager.isPlaying ? "Stop live radio" : "Play live radio")
        .accessibilityValue(song.title)
        .accessibilityHint("Controls the live radio stream.")
    }

    @ViewBuilder
    private var radioActions: some View {
        Button {
            AppHaptic.commit.play()
            audioManager.togglePlayPause()
        } label: {
            Label(
                audioManager.isPlaying ? "Stop Live Radio" : "Play Live Radio",
                systemImage: audioManager.isPlaying ? "stop.fill" : "play.fill"
            )
        }

        Button {
            AppHaptic.selection.play()
            showingQueue = true
        } label: {
            Label("Show Live Schedule", systemImage: "list.bullet")
        }

        if canFavoriteRadioSong, let songID = radioFavoriteID {
            Button {
                toggleRadioFavorite(songID)
            } label: {
                Label(
                    favorites.isFavorite(songID) ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: favorites.isFavorite(songID) ? "star.slash" : "star"
                )
            }
        }
    }

    private func toggleRadioFavorite(_ songID: String) {
        let wasFavorite = favorites.isFavorite(songID)
        favorites.toggle(songID: songID)
        if wasFavorite {
            AppHaptic.selection.play()
        } else {
            AppHaptic.success.play()
        }
    }

    private var radioFavoriteID: String? {
        radio.nowPlaying?.nowPlaying?.song.resolvedSongID
    }

    private var canFavoriteRadioSong: Bool {
        radioFavoriteID != nil && favorites.isAvailable
    }
}

/// The "LIVE RADIO" dot, breathing while the stream plays.
///
/// Sampled from an `ActiveAnimationClock` rather than a `repeatForever`
/// animation keyed on `isPlaying`: that only ever started on a *change*, so
/// opening the player while the stream was already playing left the dot sitting
/// still. The clock also freezes the pulse while the app is backgrounded or the
/// layout is parked below the screen, and resumes it in phase.
struct RadioLiveDot: View {
    let isPlaying: Bool
    /// Set while the player is closed. The layout stays mounted below the
    /// screen then, so `onDisappear` never fires and visibility alone would
    /// keep the pulse redrawing where nobody can see it; the marquees and the
    /// ambient backdrop pause on the same signal.
    var isPaused = false
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appReduceEffects) private var reduceEffects
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationClock = ActiveAnimationClock()
    @State private var isVisible = false

    /// Seconds for one full out-and-back pulse.
    private static let period: TimeInterval = 1.1

    private var shouldAnimate: Bool {
        isPlaying && isVisible && !isPaused && !reduceEffects && scenePhase == .active
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: DisplayRefreshRate.decorativeAnimationInterval,
                paused: !shouldAnimate
            )
        ) { context in
            let elapsed = animationClock.elapsed(at: context.date)
            let phase = (1 - cos(elapsed * 2 * .pi / Self.period)) / 2
            Circle()
                .fill(Color.appAccent)
                .frame(width: 7, height: 7)
                .scaleEffect(scale(phase: phase))
                // Scoped to `isPlaying` so the per-frame phase ticks stay
                // unanimated; only the settle to the idle dot eases.
                .animation(reduceMotion ? nil : AppMotion.snap, value: isPlaying)
        }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            animationClock.setRunning(false, at: .now)
        }
        .onChange(of: shouldAnimate, initial: true) { _, running in
            animationClock.setRunning(running, at: .now)
        }
    }

    private func scale(phase: Double) -> CGFloat {
        guard !reduceEffects else { return 1.0 }
        guard isPlaying else { return 0.6 }
        return 0.6 + 0.4 * phase
    }
}
