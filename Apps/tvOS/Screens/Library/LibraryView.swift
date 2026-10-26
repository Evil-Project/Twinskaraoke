import SwiftUI

struct LibraryView: View {
    let onPlay: (Song, [Song]) -> Void

    @State private var viewModel = PlaylistsViewModel()

    private let cardWidth: CGFloat = 260
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 60)]
    private let captionGap: CGFloat = 30
    private let rowGap: CGFloat = 80

    var body: some View {
        NavigationStack {
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
                title: String(localized: "No playlists yet"),
                message: String(localized: "Curated playlists will appear here.")
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
