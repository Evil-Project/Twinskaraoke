import SwiftUI

struct SearchView: View {
    let onPlay: (Song, [Song]) -> Void

    @Environment(AudioManager.self) private var audioManager
    @State private var viewModel = SearchViewModel()
    @State private var songToAdd: Song?

    var body: some View {
        @Bindable var viewModel = viewModel
        return NavigationStack {
            content
                .searchable(text: $viewModel.searchText, prompt: "Songs, artists")
        }
        .addToPlaylistSheet(song: $songToAdd)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            TVEmptyState(
                systemImage: "magnifyingglass",
                title: String(localized: "Find something to sing"),
                message: String(localized: "Search the catalog for songs and artists.")
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
                title: String(localized: "No results"),
                message: String(localized: "Try a different song or artist.")
            )
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
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
                    .contextMenu {
                        if let song {
                            TVAddToPlaylistMenuButton(song: song, selection: $songToAdd)
                        }
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
    }
}

private extension SearchSongItem {
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
