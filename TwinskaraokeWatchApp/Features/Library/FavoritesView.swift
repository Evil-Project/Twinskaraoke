import SwiftUI

struct FavoritesView: View {
    @StateObject private var viewModel = FavoritesViewModel()
    @ObservedObject private var favorites = FavoritesManager.shared
    @ObservedObject private var auth = WatchAuthManager.shared
    @EnvironmentObject var audioManager: AudioManager
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
            if auth.linkState != .signedIn {
                WatchEmptyState(
                    systemImage: "iphone",
                    title: "Sign In to See Favorites",
                    message: "Sign in on your iPhone and your starred songs appear here."
                )
                .listRowBackground(Color.clear)
            } else if viewModel.needsPhoneSession, viewModel.songs.isEmpty {
                WatchLoadErrorState(
                    title: "Waiting for iPhone",
                    message: "Your session hasn't reached this watch yet. Keep your iPhone nearby.",
                    retryAction: {
                        auth.syncNow()
                        viewModel.fetch(force: true)
                    }
                )
                .listRowBackground(Color.clear)
            } else if viewModel.isLoading, viewModel.songs.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let loadError = viewModel.loadError, viewModel.songs.isEmpty {
                WatchLoadErrorState(
                    title: "Couldn't Load Favorites",
                    message: loadError,
                    retryAction: { viewModel.fetch(force: true) }
                )
                .listRowBackground(Color.clear)
            } else if viewModel.songs.isEmpty {
                WatchEmptyState(
                    systemImage: "star",
                    title: "No Favorites",
                    message: "Songs you star show up here."
                )
                .listRowBackground(Color.clear)
            } else {
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
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            unfavorite(song)
                        } label: {
                            Label("Unstar", systemImage: "star.slash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Favorites")
        .animation(listAnimation, value: audioManager.currentSong?.id)
        .animation(playbackAnimation, value: audioManager.isPlaying)
        .animation(listAnimation, value: viewModel.songs.count)
        .navigationDestination(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(audioManager)
        }
        .onAppear {
            favorites.loadIfNeeded()
            // Forced because starring happens on this device too, from the
            // player. `favoriteSongs()` is cached and `toggle` invalidates it,
            // so an unchanged list costs a cache hit rather than a request.
            viewModel.fetch(force: true)
        }
        .compatibleOnChange(of: auth.linkState) { state in
            // Following the phone out of a session: drop the previous
            // account's list rather than leaving it on screen.
            if state == .signedIn {
                viewModel.fetch(force: true)
            } else {
                viewModel.reset()
            }
        }
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

    private func unfavorite(_ song: Song) {
        favorites.toggle(songID: song.id)
        // `FavoritesManager` rolls its own state back if the request fails, but
        // this list is a snapshot; drop the row now and let a later visit
        // re-fetch the authoritative set.
        viewModel.remove(songID: song.id)
        WatchHaptic.play(.click)
    }
}
