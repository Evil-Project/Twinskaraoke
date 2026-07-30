import SwiftUI

struct HomeView: View {
    @EnvironmentObject var audioManager: AudioManager
    @StateObject var homeViewModel = HomeViewModel()
    @ObservedObject private var auth = WatchAuthManager.shared
    @ObservedObject private var recents = RecentlyPlayedStore.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var path = NavigationPath()

    /// Everything this screen can push.
    ///
    /// The stack drives navigation from one path and one `navigationDestination`.
    /// Mixing value-based links with `navigationDestination(isPresented:)` in a
    /// single stack leaves the view-based links inert — taps land, nothing is
    /// pushed — which is what made every Browse row except Radio look dead.
    private enum Destination: Hashable {
        case player
        case playlists
        case favorites
        case songs
        case radio
        case search
        case account
    }

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
        NavigationStack(path: $path) {
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
                        NavigationLink(value: Destination.player) {
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
                    }
                }
                if !recentlyPlayed.isEmpty {
                    Section("Recently Played") {
                        ForEach(Array(recentlyPlayed.enumerated()), id: \.element.id) { index, song in
                            Button {
                                // Queue the whole history, not just the rows
                                // shown, so playing the last one keeps going.
                                play(song, context: recents.songs)
                            } label: {
                                WatchSongRow(song: song)
                            }
                            .buttonStyle(.watchPressable)
                            .accessibilityIdentifier("WatchHome.recent.\(index)")
                            .accessibilityLabel(song.title)
                            .accessibilityValue("\(song.artistName), \(song.durationText)")
                            .accessibilityHint("Double tap to play this song again.")
                        }
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
                    browseLink(
                        .playlists,
                        title: "Playlists",
                        subtitle: "Curated playlists",
                        systemImage: "music.note.list",
                        tint: .appAccent,
                        identifier: "WatchHome.playlists",
                        hint: "Opens curated playlists."
                    )
                    if auth.linkState == .signedIn {
                        browseLink(
                            .favorites,
                            title: "Favorites",
                            subtitle: "Songs you starred",
                            systemImage: "star.fill",
                            tint: .yellow,
                            identifier: "WatchHome.favorites",
                            hint: "Opens songs you starred."
                        )
                    }
                    browseLink(
                        .songs,
                        title: "Songs",
                        subtitle: "Trending songs",
                        systemImage: "music.note",
                        tint: .purple,
                        identifier: "WatchHome.songs",
                        hint: "Opens trending songs."
                    )
                    browseLink(
                        .radio,
                        title: "Radio",
                        subtitle: "Listen live",
                        systemImage: "dot.radiowaves.left.and.right",
                        tint: .orange,
                        identifier: "WatchHome.radio",
                        hint: "Opens the live station."
                    )
                    browseLink(
                        .search,
                        title: "Search",
                        subtitle: "Find songs and artists",
                        systemImage: "magnifyingglass",
                        tint: .blue,
                        identifier: "WatchHome.search",
                        hint: "Opens search."
                    )
                    browseLink(
                        .account,
                        title: "Account",
                        subtitle: accountSubtitle,
                        systemImage: "person.crop.circle",
                        tint: .green,
                        identifier: "WatchHome.account",
                        hint: "Opens account and session status."
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .animation(songStateAnimation, value: audioManager.currentSong?.id)
            .animation(playbackAnimation, value: audioManager.isPlaying)
            .navigationDestination(for: Destination.self) { destination in
                view(for: destination)
            }
            .onAppear {
                homeViewModel.fetchTrending()
            }
        }
    }

    // `title` and `hint` are keys rather than plain strings so the literals at
    // each call site still land in the string catalog. Passing them as `String`
    // hides them from extraction — the four Browse hints dropped out of
    // Localizable.xcstrings the moment these rows moved behind a helper.
    // `subtitle` stays a String: Account's is a live session status, not a key.
    private func browseLink(
        _ destination: Destination,
        title: LocalizedStringKey,
        subtitle: String,
        systemImage: String,
        tint: Color,
        identifier: String,
        hint: LocalizedStringKey
    ) -> some View {
        NavigationLink(value: destination) {
            WatchBrowseLinkRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint
            )
        }
        .accessibilityIdentifier(identifier)
        .buttonStyle(.watchPressable)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    @ViewBuilder
    private func view(for destination: Destination) -> some View {
        switch destination {
        case .player:
            PlayerView().environmentObject(audioManager)
        case .playlists:
            PlaylistsGridView()
        case .favorites:
            FavoritesView().environmentObject(audioManager)
        case .songs:
            SongsView().environmentObject(audioManager)
        case .radio:
            RadioView().environmentObject(audioManager)
        case .search:
            SearchView().environmentObject(audioManager)
        case .account:
            AccountView()
        }
    }

    /// The current song already has its own section above, so it is dropped
    /// here rather than appearing twice on one short screen.
    private var recentlyPlayed: [Song] {
        Array(
            recents.songs
                .filter { $0.id != audioManager.currentSong?.id }
                .prefix(3)
        )
    }

    private var accountSubtitle: String {
        switch auth.linkState {
        case .signedIn:
            auth.username ?? "Signed in"
        case .awaitingPhone:
            "Waiting for iPhone"
        case .signedOut:
            "Guest session"
        }
    }

    private func play(_ song: Song, context: [Song]) {
        if audioManager.currentSong?.id != song.id {
            audioManager.play(song: song, context: context)
            WatchHaptic.play(.start)
        } else {
            WatchHaptic.play(.click)
        }
        path.append(Destination.player)
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
    let title: LocalizedStringKey
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
