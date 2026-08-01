import SwiftUI

struct QueueView: View {
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var queueAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    var body: some View {
        List {
            let upNext = audioManager.upNextQueueEntries
            let upNextSongs = upNext.map(\.song)
            if let current = audioManager.currentSong {
                WatchQueueSummaryCard(
                    song: current,
                    isPlaying: audioManager.isPlaying,
                    isLoading: audioManager.isLoading,
                    progress: audioManager.progress,
                    queueSummary: WatchQueuePresentation.summary(
                        upNextSongs: upNextSongs,
                        queueCount: audioManager.queue.count,
                        playbackMode: audioManager.playbackMode
                    ),
                    playPauseAction: toggleCurrentPlayback,
                    previousAction: {
                        audioManager.playPrevious()
                        WatchHaptic.play(.previous)
                    },
                    nextAction: {
                        audioManager.playNext()
                        WatchHaptic.play(.next)
                    }
                )
                .accessibilityIdentifier("WatchQueue.summary")
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)

                Section("Now Playing") {
                    Button {
                        toggleCurrentPlayback()
                    } label: {
                        WatchSongRow(
                            song: current,
                            isCurrent: true,
                            isPlaying: audioManager.isPlaying,
                            trailingSystemImage: playbackControlSystemName,
                            artworkSize: 34
                        )
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.watchPressable)
                    .accessibilityLabel(playbackControlLabel(for: current))
                    .accessibilityValue("\(current.artistName), \(playbackStateLabel)")
                    .accessibilityHint("Controls the current song.")
                    .accessibilityIdentifier("WatchQueue.nowPlaying")
                }
            }
            if !upNext.isEmpty {
                Section("Playing Next") {
                    ForEach(Array(upNext.enumerated()), id: \.element.id) { offset, entry in
                        Button {
                            let didStart = audioManager.playQueueItem(at: entry.queueIndex)
                            WatchHaptic.play(didStart ? .start : .failure)
                        } label: {
                            WatchQueuedSongRow(song: entry.song, offset: offset, total: upNext.count)
                        }
                        .buttonStyle(.watchPressable)
                        .accessibilityLabel(entry.song.title)
                        .accessibilityValue(
                            "\(entry.song.artistName), \(queuePositionText(offset: offset, total: upNext.count)), \(entry.song.durationText)"
                        )
                        .accessibilityHint("Double tap to play this song now.")
                        .accessibilityIdentifier("WatchQueue.upNext.\(offset)")
                    }
                }
            } else {
                if audioManager.currentSong == nil {
                    WatchEmptyState(
                        systemImage: "list.bullet",
                        title: "Queue Empty",
                        message: "Play a song to build an up next queue."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    let emptyState = WatchQueuePresentation.emptyState(
                        queueCount: audioManager.queue.count,
                        playbackMode: audioManager.playbackMode
                    )
                    Section("Playing Next") {
                        WatchEmptyState(
                            systemImage: "text.line.first.and.arrowtriangle.forward",
                            title: emptyState.title,
                            message: emptyState.message
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle("Queue")
        .animation(queueAnimation, value: audioManager.currentSong?.id)
        .animation(queueAnimation, value: audioManager.queue.map(\.id))
    }

    private func toggleCurrentPlayback() {
        let wasActive = audioManager.isPlaying || audioManager.isLoading
        if audioManager.togglePlayPause() {
            WatchHaptic.play(wasActive ? .stop : .start)
        } else {
            WatchHaptic.play(.failure)
        }
    }

    private var playbackControlSystemName: String {
        if audioManager.isLoading { "stop.fill" } else if audioManager.isPlaying { "pause.fill" } else { "play.fill" }
    }

    private var playbackStateLabel: String {
        WatchPlaybackControlPresentation.stateLabel(
            isLoading: audioManager.isLoading,
            isPlaying: audioManager.isPlaying
        )
    }

    private func playbackControlLabel(for song: Song) -> String {
        WatchPlaybackControlPresentation.actionLabel(
            songTitle: song.title,
            isLoading: audioManager.isLoading,
            isPlaying: audioManager.isPlaying
        )
    }

    private func queuePositionText(offset: Int, total: Int) -> String {
        if total == 1 {
            return "Up next"
        }
        return "Up next \(offset + 1) of \(total)"
    }

}

private struct WatchQueuedSongRow: View {
    let song: Song
    let offset: Int
    let total: Int

    private var isUpNext: Bool {
        offset == 0
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                WatchSongArtwork(
                    url: song.rowImageURL,
                    size: 36,
                    cornerRadius: 8
                )

                Text("\(offset + 1)")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundColor(isUpNext ? .white : .primary)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(
                        Circle()
                            .fill(isUpNext ? Color.appAccent : Color.secondary.opacity(0.2))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    )
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: isUpNext ? "text.line.first.and.arrowtriangle.forward" : "line.3.horizontal")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isUpNext ? .appAccent : .secondary)
                        .accessibilityHidden(true)
                    Text(isUpNext ? "Up Next" : "Queued \(offset + 1) of \(total)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isUpNext ? .appAccent : .secondary)
                        .lineLimit(1)
                }

                Text(song.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(song.artistName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(song.durationText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [song.artistName]
        parts.append(isUpNext ? "Up next" : "Queued \(offset + 1) of \(total)")
        if !song.durationText.isEmpty {
            parts.append(song.durationText)
        }
        return parts.joined(separator: ", ")
    }
}

private struct WatchQueueSummaryCard: View {
    let song: Song
    let isPlaying: Bool
    let isLoading: Bool
    let progress: Double
    let queueSummary: String
    let playPauseAction: () -> Void
    let previousAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    WatchSongArtwork(
                        url: song.thumbnailURL,
                        size: 48,
                        cornerRadius: 10,
                        isCurrent: true,
                        isPlaying: isPlaying
                    )

                    if isLoading {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.34))
                            .frame(width: 48, height: 48)
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Queue")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(song.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(queueSummary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                WatchQueueProgressRing(progress: progress, isPlaying: isPlaying)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 4) {
                WatchQueueTransportButton(
                    systemName: "backward.fill",
                    diameter: 30,
                    iconSize: 13,
                    tint: .primary,
                    fill: Color.secondary.opacity(0.13),
                    accessibilityLabel: "Previous Track",
                    action: previousAction
                )

                WatchQueueTransportButton(
                    systemName: isLoading ? "stop.fill" : (isPlaying ? "pause.fill" : "play.fill"),
                    diameter: 40,
                    iconSize: 20,
                    tint: .white,
                    fill: Color.appAccent,
                    accessibilityLabel: isLoading ? "Cancel Loading" : (isPlaying ? "Pause" : "Play"),
                    action: playPauseAction
                )

                WatchQueueTransportButton(
                    systemName: "forward.fill",
                    diameter: 30,
                    iconSize: 13,
                    tint: .primary,
                    fill: Color.secondary.opacity(0.13),
                    accessibilityLabel: "Next Track",
                    action: nextAction
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Queue")
        .accessibilityValue(
            "\(song.title), \(song.artistName), \(playbackStateLabel), \(queueSummary)"
        )
    }

    private var playbackStateLabel: String {
        WatchPlaybackControlPresentation.stateLabel(
            isLoading: isLoading,
            isPlaying: isPlaying
        )
    }
}

private struct WatchQueueTransportButton: View {
    let systemName: String
    let diameter: CGFloat
    let iconSize: CGFloat
    let tint: Color
    let fill: Color
    var isDisabled = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(fill))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.watchPressable)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct WatchQueueProgressRing: View {
    let progress: Double
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    Color.appAccent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: progress)
            WatchNowPlayingGlyph(isPlaying: isPlaying)
        }
        .frame(width: 28, height: 28)
    }
}
