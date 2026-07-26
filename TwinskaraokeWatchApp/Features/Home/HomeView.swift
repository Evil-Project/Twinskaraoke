import SwiftUI

struct HomeView: View {
    @EnvironmentObject var audioManager: AudioManager
    @StateObject var homeViewModel = HomeViewModel()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var navigateToPlayer = false

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var songStateAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var playbackAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    var body: some View {
        NavigationStack {
            List {
                WatchHomeHeader(
                    isPlaying: audioManager.isPlaying,
                    currentSongTitle: audioManager.currentSong?.title
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("WatchHome.listenNow")

                if let currentSong = audioManager.currentSong {
                    Section("Now Playing") {
                        NavigationLink(destination: PlayerView().environmentObject(audioManager)) {
                            WatchSongRow(
                                song: currentSong,
                                isCurrent: true,
                                isPlaying: audioManager.isPlaying,
                                trailingSystemImage: audioManager.isPlaying ? "pause.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(.watchPressable)
                        .accessibilityLabel("Now Playing")
                        .accessibilityValue("\(currentSong.title), \(currentSong.artistName), \(audioManager.isPlaying ? "Playing" : "Paused")")
                        .accessibilityHint("Double tap to open the player.")
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                WatchHaptic.play(.click)
                            }
                        )
                    }
                }
                if !homeViewModel.trending.isEmpty {
                    Section("Trending") {
                        ForEach(Array(homeViewModel.trending.prefix(5).enumerated()), id: \.element.id) { index, song in
                            let isCurrent = audioManager.currentSong?.id == song.id
                            Button {
                                play(song, context: homeViewModel.trending)
                            } label: {
                                WatchSongRow(
                                    song: song,
                                    isCurrent: isCurrent,
                                    isPlaying: isCurrent && audioManager.isPlaying,
                                    trailingSystemImage: isCurrent
                                        ? (audioManager.isPlaying ? "pause.fill" : "play.fill")
                                        : nil
                                )
                            }
                            .buttonStyle(.watchPressable)
                            .accessibilityIdentifier("WatchHome.trending.\(index)")
                            .accessibilityLabel(isCurrent && audioManager.isPlaying ? "Open \(song.title)" : song.title)
                            .accessibilityValue("\(song.artistName), \(song.durationText)")
                            .accessibilityHint(isCurrent ? "Double tap to open the current song." : "Double tap to play this song.")
                        }
                    }
                } else if homeViewModel.isLoading {
                    Section("Trending") {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                Section("Browse") {
                    NavigationLink(destination: PlaylistsGridView()) {
                        WatchBrowseLinkRow(
                            title: "Playlists",
                            subtitle: "Curated playlists",
                            systemImage: "music.note.list",
                            tint: .appAccent
                        )
                    }
                    .accessibilityIdentifier("WatchHome.playlists")
                    .buttonStyle(.watchPressable)
                    .accessibilityLabel("Playlists")
                    .accessibilityHint("Opens curated playlists.")
                    .simultaneousGesture(TapGesture().onEnded { WatchHaptic.play(.click) })
                    NavigationLink(destination: SongsView().environmentObject(audioManager)) {
                        WatchBrowseLinkRow(
                            title: "Songs",
                            subtitle: "Trending songs",
                            systemImage: "music.note",
                            tint: .purple
                        )
                    }
                    .accessibilityIdentifier("WatchHome.songs")
                    .buttonStyle(.watchPressable)
                    .accessibilityLabel("Songs")
                    .accessibilityHint("Opens trending songs.")
                    .simultaneousGesture(TapGesture().onEnded { WatchHaptic.play(.click) })
                    NavigationLink(destination: SearchView().environmentObject(audioManager)) {
                        WatchBrowseLinkRow(
                            title: "Search",
                            subtitle: "Find songs and artists",
                            systemImage: "magnifyingglass",
                            tint: .blue
                        )
                    }
                    .accessibilityIdentifier("WatchHome.search")
                    .buttonStyle(.watchPressable)
                    .accessibilityLabel("Search")
                    .accessibilityHint("Opens search.")
                    .simultaneousGesture(TapGesture().onEnded { WatchHaptic.play(.click) })
                    NavigationLink(destination: AccountView()) {
                        WatchBrowseLinkRow(
                            title: "Account",
                            subtitle: "Guest session",
                            systemImage: "person.crop.circle",
                            tint: .green
                        )
                    }
                    .accessibilityIdentifier("WatchHome.account")
                    .buttonStyle(.watchPressable)
                    .accessibilityLabel("Account")
                    .accessibilityHint("Opens account and session status.")
                    .simultaneousGesture(TapGesture().onEnded { WatchHaptic.play(.click) })
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .animation(songStateAnimation, value: audioManager.currentSong?.id)
            .animation(playbackAnimation, value: audioManager.isPlaying)
            .navigationDestination(isPresented: $navigateToPlayer) {
                PlayerView()
                    .environmentObject(audioManager)
            }
            .onAppear {
                homeViewModel.fetchTrending()
            }
        }
    }

    private func play(_ song: Song, context: [Song]) {
        if audioManager.currentSong?.id != song.id {
            audioManager.play(song: song, context: context)
            WatchHaptic.play(.start)
        } else {
            WatchHaptic.play(.click)
        }
        navigateToPlayer = true
    }
}

private struct WatchHomeHeader: View {
    let isPlaying: Bool
    let currentSongTitle: String?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.appAccent)
                Image(systemName: isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Listen Now")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Listen Now")
        .accessibilityValue(statusText)
    }

    private var statusText: String {
        guard let currentSongTitle, !currentSongTitle.isEmpty else {
            return "Trending and library"
        }
        return isPlaying ? "Playing \(currentSongTitle)" : "Paused \(currentSongTitle)"
    }
}

private struct WatchBrowseLinkRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}
