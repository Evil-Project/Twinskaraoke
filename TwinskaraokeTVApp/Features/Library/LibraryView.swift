import SwiftUI

struct LibraryView: View {
    let onPlay: (Song, [Song]) -> Void

    @State private var viewModel = PlaylistsViewModel()

    private let cardWidth: CGFloat = 260
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 60)]
    /// The `.card` focus lift scales a poster up in place, so each cell needs
    /// slack above and below its artwork or a focused card grows into the
    /// caption under it and the row of posters above.
    private let captionGap: CGFloat = 30
    private let rowGap: CGFloat = 80

    var body: some View {
        NavigationStack {
            // No `.navigationTitle`: the tab bar already labels this screen,
            // and on tvOS the title floats over the scroll content rather than
            // reserving space for itself — it drifts across the artwork.
            content
                .navigationDestination(for: Playlist.self) { playlist in
                    PlaylistDetailView(playlist: playlist, onPlay: onPlay)
                }
        }
        .onAppear { viewModel.fetch() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.loadError, viewModel.playlists.isEmpty {
            TVLoadErrorState(message: error) { viewModel.fetch() }
        } else if viewModel.playlists.isEmpty && viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.playlists.isEmpty {
            TVEmptyState(
                systemImage: "music.note.list",
                title: "No playlists yet",
                message: "Curated playlists will appear here."
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: rowGap) {
                    ForEach(viewModel.playlists) { playlist in
                        VStack(alignment: .leading, spacing: captionGap) {
                            NavigationLink(value: playlist) {
                                TVArtwork(url: playlist.imageURL)
                                    .frame(width: cardWidth, height: cardWidth)
                            }
                            .buttonStyle(.card)
                            .accessibilityLabel(playlist.name)
                            .accessibilityValue(playlist.songCountText)

                            TVPosterCaption(
                                title: playlist.name,
                                subtitle: playlist.songCountText,
                                width: cardWidth
                            )
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
        }
    }
}
