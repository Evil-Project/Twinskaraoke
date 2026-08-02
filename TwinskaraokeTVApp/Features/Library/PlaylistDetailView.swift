import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    let onPlay: (Song, [Song]) -> Void

    @Environment(AudioManager.self) private var audioManager
    @State private var viewModel: PlaylistDetailViewModel

    init(playlist: Playlist, onPlay: @escaping (Song, [Song]) -> Void) {
        self.playlist = playlist
        self.onPlay = onPlay
        _viewModel = State(initialValue: PlaylistDetailViewModel(playlistID: playlist.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header
                songList
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        // No `.navigationTitle` here on purpose: the 56pt name in `header` is
        // the title for this screen, and setting both renders the playlist name
        // twice, with the nav-bar copy sliding around during the push
        // transition and on scroll.
        .onAppear { viewModel.fetchSongs() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 40) {
            TVArtwork(url: playlist.imageURL)
                .frame(width: 320, height: 320)
                .shadow(radius: 24)

            VStack(alignment: .leading, spacing: 16) {
                Text(playlist.name)
                    .font(.system(size: 56, weight: .bold))
                    .lineLimit(2)
                Text(playlist.songCountText)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button {
                    if let first = viewModel.songs.first {
                        onPlay(first, viewModel.songs)
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.songs.isEmpty)
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var songList: some View {
        if let error = viewModel.loadError, viewModel.songs.isEmpty {
            TVLoadErrorState(message: error) { viewModel.fetchSongs() }
                .frame(height: 400)
        } else if viewModel.songs.isEmpty && viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 400)
        } else {
            // Enough gap for the focus pill, which scales slightly past the
            // row's own bounds — at a tighter spacing it laps onto the artwork
            // of the rows either side.
            LazyVStack(spacing: 16) {
                // Keyed by position, not song id: a playlist may legitimately
                // list the same song twice, and duplicate SwiftUI identities
                // drop or mis-animate rows.
                ForEach(Array(viewModel.songs.enumerated()), id: \.offset) { index, song in
                    let isCurrent = audioManager.currentSong?.id == song.id
                    TVSongRow(
                        index: index + 1,
                        song: song,
                        isCurrent: isCurrent,
                        isPlaying: isCurrent && audioManager.isPlaying
                    ) {
                        onPlay(song, viewModel.songs)
                    }
                }
            }
        }
    }
}
