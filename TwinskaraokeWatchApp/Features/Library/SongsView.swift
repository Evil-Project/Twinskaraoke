import SwiftUI

struct SongsView: View {
    @State var viewModel = SongsViewModel()
    @Environment(AudioManager.self) var audioManager
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var showPlayer = false

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private var playbackAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    var body: some View {
        List {
            if viewModel.isLoading, viewModel.songs.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let loadError = viewModel.loadError, viewModel.songs.isEmpty {
                WatchLoadErrorState(
                    title: "Couldn't Load Songs",
                    message: loadError,
                    retryAction: { viewModel.fetchSongs() }
                )
                .listRowBackground(Color.clear)
            } else if viewModel.songs.isEmpty {
                WatchEmptyState(
                    systemImage: "music.note.list",
                    title: "No Songs",
                    message: "Trending songs will appear here."
                )
                .listRowBackground(Color.clear)
            } else {
                WatchSongsLibraryHeader(
                    songCount: viewModel.songs.count,
                    durationText: totalDurationText,
                    isLoading: viewModel.isLoading,
                    playAction: playFirstSong,
                    shuffleAction: shuffleAllSongs
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)

                ForEach(viewModel.songs) { song in
                    let isCurrent = audioManager.currentSong?.id == song.id
                    Button {
                        play(song)
                    } label: {
                        WatchSongRow(
                            song: song,
                            isCurrent: isCurrent,
                            isPlaying: isCurrent && audioManager.isPlaying,
                            showsDuration: !isCurrent,
                            trailingSystemImage: isCurrent
                                ? (audioManager.isPlaying ? "pause.fill" : "play.fill")
                                : nil
                        )
                    }
                    .buttonStyle(.watchPressable)
                    .accessibilityLabel(isCurrent && audioManager.isPlaying ? "Pause \(song.title)" : song.title)
                    .accessibilityHint(isCurrent ? "Double tap to open the current song." : "Double tap to play this song.")
                }
            }
        }
        .navigationTitle("Trending")
        .animation(listAnimation, value: audioManager.currentSong?.id)
        .animation(playbackAnimation, value: audioManager.isPlaying)
        .animation(listAnimation, value: viewModel.songs.count)
        .animation(playbackAnimation, value: viewModel.isLoading)
        .navigationDestination(isPresented: $showPlayer) {
            PlayerView()
                .environment(audioManager)
        }
        .onAppear {
            viewModel.fetchSongs()
        }
    }

    private var totalDurationText: String {
        let totalSeconds = viewModel.songs.reduce(0) { $0 + max(0, $1.duration) }
        guard totalSeconds > 0 else { return "0:00" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func play(_ song: Song) {
        if audioManager.currentSong?.id != song.id {
            audioManager.play(song: song, context: viewModel.songs)
            WatchHaptic.play(.start)
        } else {
            WatchHaptic.play(.click)
        }
        showPlayer = true
    }

    private func playFirstSong() {
        guard let firstSong = viewModel.songs.first else {
            WatchHaptic.play(.failure)
            return
        }
        if audioManager.isShuffleOn {
            audioManager.toggleShuffle()
        }
        play(firstSong)
    }

    private func shuffleAllSongs() {
        guard let randomSong = viewModel.songs.randomElement() else {
            WatchHaptic.play(.failure)
            return
        }
        if !audioManager.isShuffleOn {
            audioManager.toggleShuffle()
        }
        audioManager.play(song: randomSong, context: viewModel.songs)
        WatchHaptic.play(.start)
        showPlayer = true
    }
}

private struct WatchSongsLibraryHeader: View {
    let songCount: Int
    let durationText: String
    let isLoading: Bool
    let playAction: () -> Void
    let shuffleAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.appAccent.opacity(0.16))
                    Image(systemName: "music.note.list")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.appAccent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trending")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(summaryText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 8) {
                WatchSongsHeaderButton(
                    title: "Play",
                    systemName: "play.fill",
                    tint: .white,
                    fill: Color.appAccent,
                    action: playAction
                )

                WatchSongsHeaderButton(
                    title: "Shuffle",
                    systemName: "shuffle",
                    tint: .appAccent,
                    fill: Color.appAccent.opacity(0.14),
                    action: shuffleAction
                )
            }
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
        .accessibilityLabel("Trending")
        .accessibilityValue(summaryText)
    }

    private var summaryText: String {
        let countText = songCount == 1 ? "1 song" : "\(songCount) songs"
        return "\(countText) - \(durationText)"
    }
}

private struct WatchSongsHeaderButton: View {
    let title: String
    let systemName: String
    let tint: Color
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundColor(tint)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fill)
                )
        }
        .buttonStyle(.watchPressable)
        .accessibilityLabel(title)
    }
}
