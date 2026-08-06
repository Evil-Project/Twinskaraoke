import SwiftUI

struct UploadedSongsView: View {
    @State private var viewModel = UploadedSongsViewModel()
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var prefetchedIDs: [String] = []

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
            prompt: "Search Uploads"
        )
        // Collapses to a toolbar button until tapped, keeping the list the focus.
        // The Search tab keeps its field expanded — searching is the point there.
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }
        }
        .refreshable {
            AppHaptic.selection.play()
            await viewModel.refresh()
            AppHaptic.success.play()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        // Diffing on displayedSongs (Equatable, id-only ==) avoids allocating
        // the prefix id array on every body eval; it only builds when the list changes.
        .onChange(of: viewModel.displayedSongs) { _, newSongs in
            let visible = Array(newSongs.prefix(18))
            let ids = visible.map(\.id)
            guard ids != prefetchedIDs else { return }
            prefetchedIDs = ids
            ArtworkPrefetcher.shared.prefetchSongs(
                visible,
                limit: 18,
                reason: "uploaded visible songs",
                variant: .row
            )
        }
        .onDisappear {
            ArtworkPrefetcher.shared.cancel(reason: "uploaded visible songs")
        }
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
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .commit))
            .accessibilityLabel("Play uploaded songs")

            Button {
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .commit))
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
