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
    let artSize: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            PlayerArtworkView(song: song, size: artSize)
                .contextMenu {
                    radioActions
                } preview: {
                    SongContextPreview(song: song)
                }
            Spacer(minLength: 28)
            headerRow
                .padding(.horizontal, 32)
                .contextMenu {
                    radioActions
                } preview: {
                    SongContextPreview(song: song)
                }
            Spacer(minLength: 10)
            playStopButton
            Spacer(minLength: 24)
            PlayerVolumeRow()
            PlayerBottomToolbar(
                showingQueue: $showingQueue,
                song: song,
                onLyricsToggle: {},
                showLyrics: false
            )
            Spacer(minLength: 8)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RadioLiveDot(isPlaying: audioManager.isPlaying)
                    Text("LIVE RADIO")
                        .font(.caption.bold())
                        .foregroundStyle(Color.appAccent)
                        .tracking(1.2)
                    if let listeners = radio.nowPlaying?.listeners {
                        Text("·")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                        Text("\(listeners.unique) listening")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            Menu {
                SleepTimerMenu()
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
            if canFavoriteRadioSong, let songID = radioFavoriteID {
                Button {
                    toggleRadioFavorite(songID)
                } label: {
                    Group {
                        let isFav = favorites.isFavorite(songID)
                        if !reduceMotion {
                            Image(systemName: isFav ? "star.fill" : "star")
                                .contentTransition(.symbolEffect(.replace))
                        } else {
                            Image(systemName: isFav ? "star.fill" : "star")
                        }
                    }
                    .font(.title2)
                    .foregroundStyle(favorites.isFavorite(songID) ? Color.appAccent : .primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
                .accessibilityLabel(
                    favorites.isFavorite(songID) ? "Remove from Favorites" : "Add to Favorites"
                )
                .accessibilityValue(song.title)
                .accessibilityHint("Updates favorites for the current radio song.")
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
        radioFavoriteID != nil
    }
}

/// The "LIVE RADIO" dot, breathing while the stream plays.
///
/// Sampled from an `ActiveAnimationClock` rather than a `repeatForever`
/// animation keyed on `isPlaying`: that only ever started on a *change*, so
/// opening the player while the stream was already playing left the dot sitting
/// still. The clock also freezes the pulse while the app is backgrounded or the
/// layout is parked below the screen, and resumes it in phase.
private struct RadioLiveDot: View {
    let isPlaying: Bool
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appReduceEffects) private var reduceEffects
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationClock = ActiveAnimationClock()
    @State private var isVisible = false

    /// Seconds for one full out-and-back pulse.
    private static let period: TimeInterval = 1.1

    private var shouldAnimate: Bool {
        isPlaying && isVisible && !reduceEffects && scenePhase == .active
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
