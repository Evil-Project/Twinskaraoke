import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var audioManager: AudioManager
    @StateObject private var lyrics = TVLyricsViewModel()
    @FocusState private var focusedTransportControl: TVTransportControl?

    var body: some View {
        ZStack {
            background
            if audioManager.currentSong == nil {
                TVEmptyState(
                    systemImage: "play.circle",
                    title: "Nothing playing",
                    message: "Pick a song from Home, Search, or your Library to start."
                )
            } else {
                content
            }
        }
        .task(id: audioManager.currentSong?.id) {
            guard let id = audioManager.currentSong?.id else {
                lyrics.clear()
                return
            }
            lyrics.load(songID: id)
        }
    }

    @ViewBuilder
    private var background: some View {
        if let url = audioManager.currentSong?.heroImageURL {
            TVRemoteImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.black
            }
            .ignoresSafeArea()
            .blur(radius: 80)
            // Heavier than it needs to be for artwork alone: the lyrics are the
            // thing being read now, and a pale cover blurred out to near-white
            // left the dimmed past/upcoming lines barely legible against it.
            .overlay(Color.black.opacity(0.72).ignoresSafeArea())
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        if showsLyrics {
            HStack(alignment: .top, spacing: 72) {
                // Fixed width rather than a share of the screen: the transport
                // row is the widest thing in this column and it has a hard
                // minimum, so the column is sized to fit it and the lyrics take
                // whatever is left.
                VStack(alignment: .leading, spacing: 28) {
                    artwork(size: 420)
                    trackInfo(titleSize: 38)
                    progress
                    transport(spacing: 36)
                    Spacer(minLength: 0)
                }
                // Wide enough for the focused transport button's pill, which
                // spreads well past the 88pt button it wraps — at a narrower
                // column the focused Repeat control lapped over the lyrics.
                .frame(width: 640, alignment: .leading)

                TVLyricsView(
                    lyrics: lyrics.lyrics,
                    currentTime: audioManager.currentTime,
                    isLoading: lyrics.isLoading,
                    didFail: lyrics.didFail,
                    hasNoLyrics: lyrics.hasNoLyrics,
                    onRetry: { lyrics.retry() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 100)
            // Small, because `containerRelativeFrame` below measures the tab
            // content area, which is already inset for the floating tab bar —
            // this only has to clear the last few points of it.
            .padding(.top, 56)
            .padding(.bottom, 40)
            // Pins the page to one screenful. tvOS hosts tab content in a
            // scrolling container, which proposes unbounded height — so the
            // lyrics panel's `maxHeight: .infinity` resolved to the height of
            // the *entire* lyric list instead of the viewport. That made the
            // whole page taller than the screen, and the artwork and controls
            // scrolled away off the top along with the lyrics.
            .containerRelativeFrame(.vertical)
        } else {
            HStack(spacing: 80) {
                artwork(size: 460)
                VStack(alignment: .leading, spacing: 32) {
                    trackInfo(titleSize: 52)
                    progress
                    transport(spacing: 40)
                    upNext
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 80)
        }
    }

    /// The lyrics panel claims half the screen, so it only earns that space when
    /// there is something to put in it. A song the catalog has no lyrics for
    /// falls back to the original wide layout instead of parking a permanent
    /// "no lyrics" placeholder next to the artwork.
    private var showsLyrics: Bool {
        !lyrics.hasNoLyrics
    }

    private func artwork(size: CGFloat) -> some View {
        TVArtwork(url: audioManager.currentSong?.imageURL, cornerRadius: 20)
            .frame(width: size, height: size)
            .shadow(radius: 30)
    }

    /// Sized by the caller: the title has a narrower column to live in once the
    /// lyrics panel is on screen, and at 52pt a normal song title wrapped past
    /// two lines and got truncated.
    private func trackInfo(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(audioManager.currentSong?.title ?? "")
                .font(.system(size: titleSize, weight: .bold))
                .lineLimit(2)
            Text(audioManager.currentSong?.artistName ?? "")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var progress: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(Color.appAccent)
                        .frame(width: proxy.size.width * audioManager.progress)
                }
            }
            .frame(height: 8)

            HStack {
                Text(timeText(audioManager.currentTime))
                Spacer()
                Text(timeText(audioManager.duration))
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func transport(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            transportButton(
                .shuffle,
                systemImage: "shuffle",
                isActive: audioManager.isShuffleOn,
                accessibilityLabel: audioManager.isShuffleOn ? "Turn Shuffle Off" : "Turn Shuffle On"
            ) {
                audioManager.toggleShuffle()
            }

            transportButton(
                .previous,
                systemImage: "backward.fill",
                accessibilityLabel: "Previous Track"
            ) {
                audioManager.playPrevious()
            }

            transportButton(
                .playPause,
                systemImage: audioManager.isPlaying ? "pause.fill" : "play.fill",
                iconWidth: 60,
                accessibilityLabel: audioManager.isPlaying ? "Pause" : "Play"
            ) {
                audioManager.togglePlayPause()
            }

            transportButton(
                .next,
                systemImage: "forward.fill",
                accessibilityLabel: "Next Track"
            ) {
                audioManager.playNextOrRandom()
            }

            transportButton(
                .repeatMode,
                systemImage: audioManager.playbackMode.iconName,
                isActive: audioManager.playbackMode == .singleLoop,
                accessibilityLabel: "Repeat Mode"
            ) {
                audioManager.toggleMode()
            }
        }
        .font(.system(size: 40, weight: .semibold))
        .focusSection()
    }

    private func transportButton(
        _ control: TVTransportControl,
        systemImage: String,
        iconWidth: CGFloat = 44,
        isActive: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedTransportControl == control

        return Button(action: action) {
            Image(systemName: systemImage)
                .symbolVariant(isActive ? .fill : .none)
                .foregroundStyle(transportForeground(isActive: isActive, isFocused: isFocused))
                .frame(width: iconWidth, height: 54)
                .frame(width: 88, height: 88)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedTransportControl, equals: control)
        .scaleEffect(isFocused ? 1.18 : 1)
        .shadow(color: isFocused ? .white.opacity(0.35) : .clear, radius: 16)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .accessibilityLabel(accessibilityLabel)
    }

    private func transportForeground(isActive: Bool, isFocused: Bool) -> Color {
        if isActive {
            return .appAccent
        }
        return isFocused ? .white : .primary.opacity(0.82)
    }

    @ViewBuilder
    private var upNext: some View {
        if !audioManager.upNextSongs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Up Next")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ForEach(audioManager.upNextSongs.prefix(3)) { song in
                    HStack(spacing: 12) {
                        Text(song.title)
                            .font(.body)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(song.artistName)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private enum TVTransportControl: Hashable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
}
