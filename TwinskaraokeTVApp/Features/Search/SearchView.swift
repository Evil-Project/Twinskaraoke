import SwiftUI

struct SearchView: View {
    let onPlay: (Song, [Song]) -> Void

    @EnvironmentObject private var audioManager: AudioManager
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        NavigationStack {
            // See `LibraryView`: the tab bar labels this screen, and a tvOS nav
            // title floats over the scroll content instead of reserving space.
            content
                .searchable(text: $viewModel.searchText, prompt: "Songs, artists")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            TVEmptyState(
                systemImage: "magnifyingglass",
                title: "Find something to sing",
                message: "Search the catalog for songs and artists."
            )
        } else if viewModel.isLoading && viewModel.resolvedResults.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.loadError, viewModel.resolvedResults.isEmpty {
            TVLoadErrorState(message: error) {
                viewModel.performSearch(query: viewModel.searchText)
            }
        } else if viewModel.resolvedResults.isEmpty {
            TVEmptyState(
                systemImage: "questionmark.circle",
                title: "No results",
                message: "Try a different song or artist."
            )
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            // Matches `PlaylistDetailView`: clearance for the focus pill's lift.
            LazyVStack(spacing: 16) {
                // Keyed by position, not result id — see `PlaylistDetailView`.
                // Results can repeat an item across sources, and positional
                // identity also keeps focus put as the query is refined.
                ForEach(Array(viewModel.resolvedResults.enumerated()), id: \.offset) { index, result in
                    let song = result.song
                    let isCurrent = song.map { audioManager.currentSong?.id == $0.id } ?? false
                    TVSongRow(
                        index: index + 1,
                        song: song ?? result.item.asDisplaySong,
                        isCurrent: isCurrent,
                        isPlaying: isCurrent && audioManager.isPlaying
                    ) {
                        guard let song else { return }
                        onPlay(song, viewModel.playableSongs)
                    }
                    .disabled(song == nil)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
    }
}

private extension SearchSongItem {
    /// A non-playable display stand-in for oss-only / unplayable results so the
    /// row still renders title and artwork while being disabled.
    var asDisplaySong: Song {
        Song(
            id: id,
            title: title,
            duration: duration,
            absolutePath: absolutePath,
            cloudflareID: cloudflareId,
            coverArt: coverArt.map { Media(absolutePath: $0.absolutePath) },
            originalArtists: originalArtists,
            coverArtists: coverArtists,
            userUploaded: nil,
            oss: oss
        )
    }
}
