import SwiftUI

struct UploadedSongsView: View {
    @StateObject private var viewModel = UploadedSongsViewModel()
    @Environment(\.appReduceMotion) private var reduceMotion

    private var listAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }

    var body: some View {
        let songs = viewModel.displayedSongs
        let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        List {
            if viewModel.isLoading, songs.isEmpty {
                loadingRow
            } else if songs.isEmpty {
                emptyState(isSearching: isSearching)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    actionButtons(songs: songs)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    ForEach(songs) { song in
                        Button {
                            play(song, context: songs)
                        } label: {
                            SongRow(song: song, size: .regular, showsArtwork: true)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .songRowAccessibility(song: song) {
                                    play(song, context: songs)
                                }
                        }
                        .id(song.id)
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle("Uploaded")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Uploads"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }
        }
        .refreshable {
            AppHaptic.selection.play()
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onChange(of: Array(songs.prefix(18)).map(\.id)) { _, _ in
            ArtworkPrefetcher.shared.prefetchSongs(
                Array(songs.prefix(18)),
                limit: 18,
                reason: "uploaded visible songs",
                variant: .row
            )
        }
        .onDisappear {
            ArtworkPrefetcher.shared.cancel(reason: "uploaded visible songs")
        }
        .animation(listAnimation, value: songs.map(\.id))
        .animation(listAnimation, value: viewModel.sort)
        .accessibilityIdentifier("Library.UploadedSongs")
    }

    private func play(_ song: Song, context: [Song]) {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: context)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LibrarySongSort.allCases) { sort in
                Button {
                    AppHaptic.selection.play()
                    viewModel.sort = sort
                } label: {
                    Label(sort.title, systemImage: viewModel.sort == sort ? "checkmark" : sort.symbol)
                }
            }
        } label: {
            Label("Sort Uploaded Songs", systemImage: "arrow.up.arrow.down")
                .font(.headline)
                .foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .labelStyle(.iconOnly)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72, haptic: .selection))
    }

    private func actionButtons(songs: [Song]) -> some View {
        HStack(spacing: 12) {
            Button {
                if let first = songs.first {
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
            .accessibilityLabel("Play uploaded songs")

            Button {
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
            .accessibilityLabel("Shuffle uploaded songs")
        }
    }

    private func emptyState(isSearching: Bool) -> some View {
        VStack(spacing: AM.Spacing.l) {
            MusicEmptyState(title: emptyTitle(isSearching: isSearching), message: emptyMessage(isSearching: isSearching))

            if viewModel.loadFailed {
                MusicEmptyActionButton(title: "Try Again") {
                    Task {
                        await viewModel.refresh()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func emptyTitle(isSearching: Bool) -> String {
        if isSearching { return "No Results" }
        if viewModel.requiresSignIn { return "Sign In Required" }
        if viewModel.loadFailed { return "Couldn't Load Uploads" }
        return "No Uploads"
    }

    private func emptyMessage(isSearching: Bool) -> String {
        if isSearching { return "Try another song or artist." }
        if viewModel.requiresSignIn {
            return "Sign in from Account to see the songs you've uploaded, then pull to refresh."
        }
        if viewModel.loadFailed { return "Check your connection and try again." }
        return "Songs uploaded through Twins Karaoke will appear here."
    }

    private var loadingRow: some View {
        CenteredLoadingView()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
