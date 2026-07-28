import SwiftUI

struct PlaylistDetailView: View {
    @StateObject var viewModel: PlaylistDetailViewModel
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var showPlayer = false
    let playlistName: String

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

    init(playlistID: String, playlistName: String) {
        self.playlistName = playlistName
        _viewModel = StateObject(wrappedValue: PlaylistDetailViewModel(playlistID: playlistID))
    }

    var body: some View {
        List {
            if viewModel.isLoading, viewModel.songs.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let loadError = viewModel.loadError, viewModel.songs.isEmpty {
                WatchLoadErrorState(
                    title: "Couldn't Load Playlist",
                    message: loadError,
                    retryAction: { viewModel.fetchSongs() }
                )
                .listRowBackground(Color.clear)
            } else if viewModel.songs.isEmpty {
                WatchEmptyState(
                    systemImage: "music.note.list",
                    title: "Playlist Empty",
                    message: "Songs added to \(playlistName) will appear here."
                )
                .listRowBackground(Color.clear)
            } else {
                WatchPlaylistDetailHeader(
                    playlistName: playlistName,
                    songCountText: songCountText,
                    durationText: totalDurationText,
                    isLoading: viewModel.isLoading,
                    playAction: playFirstSong,
                    shuffleAction: shufflePlaylist
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)

                Section {
                    ForEach(indexedSongs) { item in
                        let offset = item.offset
                        let song = item.song
                        let isCurrent = audioManager.currentSong?.id == song.id
                        Button {
                            play(song)
                        } label: {
                            WatchSongRow(
                                song: song,
                                isCurrent: isCurrent,
                                isPlaying: isCurrent && audioManager.isPlaying,
                                showsDuration: !isCurrent,
                                trailingSystemImage: isCurrent ? (audioManager.isPlaying ? "pause.fill" : "play.fill") : nil,
                                artworkSize: 38
                            )
                        }
                        .buttonStyle(.watchPressable)
                        .accessibilityLabel(isCurrent && audioManager.isPlaying ? "Pause \(song.title)" : song.title)
                        .accessibilityValue(accessibilityValue(for: song, offset: offset, isCurrent: isCurrent))
                        .accessibilityHint(isCurrent ? "Double tap to open the current song." : "Double tap to play from \(playlistName).")
                    }
                } footer: {
                    Text(songCountText)
                }
            }
        }
        .navigationTitle(playlistName)
        .animation(listAnimation, value: audioManager.currentSong?.id)
        .animation(playbackAnimation, value: audioManager.isPlaying)
        .animation(listAnimation, value: viewModel.songs.count)
        .animation(playbackAnimation, value: viewModel.isLoading)
        .navigationDestination(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(audioManager)
        }
        .onAppear {
            viewModel.fetchSongs()
        }
    }

    // Karaoke setlists legitimately repeat a song and Song identity is the id
    // alone, so rows use a composite id to keep ForEach identifiers unique.
    private var indexedSongs: [PlaylistSongRowItem] {
        viewModel.songs.enumerated().map { offset, song in
            PlaylistSongRowItem(id: "\(song.id)#\(offset)", offset: offset, song: song)
        }
    }

    private var songCountText: String {
        let count = viewModel.songs.count
        if count == 1 { return "1 song" }
        return "\(count) songs"
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

    private func shufflePlaylist() {
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

    private func accessibilityValue(for song: Song, offset: Int, isCurrent: Bool) -> String {
        var parts = [song.artistName, "Track \(offset + 1) of \(viewModel.songs.count)"]
        if isCurrent {
            parts.append(audioManager.isPlaying ? "Playing" : "Paused")
        } else {
            parts.append(song.durationText)
        }
        return parts.joined(separator: ", ")
    }
}

private struct WatchPlaylistDetailHeader: View {
    let playlistName: String
    let songCountText: String
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
                    Text(playlistName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
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
                WatchPlaylistHeaderButton(
                    title: "Play",
                    systemName: "play.fill",
                    tint: .white,
                    fill: Color.appAccent,
                    action: playAction
                )

                WatchPlaylistHeaderButton(
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
        .accessibilityLabel(playlistName)
        .accessibilityValue(summaryText)
    }

    private var summaryText: String {
        "\(songCountText) - \(durationText)"
    }
}

private struct WatchPlaylistHeaderButton: View {
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


private struct PlaylistSongRowItem: Identifiable {
    let id: String
    let offset: Int
    let song: Song
}
