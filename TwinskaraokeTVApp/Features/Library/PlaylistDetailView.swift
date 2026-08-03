import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    let onPlay: (Song, [Song]) -> Void

    @Environment(AudioManager.self) private var audioManager
    @State private var viewModel: PlaylistDetailViewModel
    @State private var songToAdd: Song?
    private let userPlaylists = TVUserPlaylistsManager.shared

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
        .onAppear {
            viewModel.fetchSongs()
            // The removal item is gated on this list; without the warm-up it
            // stays hidden when the playlist was opened from the Library tab
            // rather than the Playlists tab.
            userPlaylists.loadIfNeeded()
        }
        .addToPlaylistSheet(song: $songToAdd)
        .alert(
            "Couldn’t remove song",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.actionError ?? "")
        }
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
        } else if viewModel.songs.isEmpty {
            // A playlist created on this Apple TV starts empty, so this is a
            // state users reach immediately rather than an edge case.
            TVEmptyState(
                systemImage: "music.note.list",
                title: "No songs yet",
                message: "Add songs to this playlist from the Twinskaraoke app on your phone, tablet, or the web."
            )
            .frame(height: 400)
        } else {
            // Enough gap for the focus pill, which scales slightly past the
            // row's own bounds — at a tighter spacing it laps onto the artwork
            // of the rows either side.
            LazyVStack(spacing: 16) {
                // Keyed by position, not song id: a playlist may legitimately
                // list the same song twice, and duplicate SwiftUI identities
                // drop or mis-animate rows.
                ForEach(Array(viewModel.songs.enumerated()), id: \.offset) { index, song in
                    row(for: song, at: index)
                }
            }
        }
    }

    /// Long-pressing the remote's select button opens the context menu. Adding
    /// to another playlist works anywhere; removing is offered only on the
    /// user's own playlists — a curated one isn't theirs to edit.
    private func row(for song: Song, at index: Int) -> some View {
        let isCurrent = audioManager.currentSong?.id == song.id
        return TVSongRow(
            index: index + 1,
            song: song,
            isCurrent: isCurrent,
            isPlaying: isCurrent && audioManager.isPlaying
        ) {
            onPlay(song, viewModel.songs)
        }
        .contextMenu {
            TVAddToPlaylistMenuButton(song: song, selection: $songToAdd)

            if canRemoveSongs {
                Button(role: .destructive) {
                    viewModel.removeSong(at: index)
                } label: {
                    Label("Remove from Playlist", systemImage: "minus.circle")
                }
            }
        }
        .accessibilityAction(named: "Add to Playlist") {
            songToAdd = song
        }
        .accessibilityAction(named: "Remove from Playlist") {
            guard canRemoveSongs else { return }
            viewModel.removeSong(at: index)
        }
    }

    /// Membership in `/api/user/playlists` is the whole ownership test. The
    /// payload's `editable`/`deletable` flags are not usable: the server
    /// returns false for both even on playlists the signed-in user created.
    /// `isPersonal` is only set on the instances `PlaylistsView` builds, so it
    /// would hide the action on the same playlist opened from the Library tab.
    private var canRemoveSongs: Bool {
        guard playlist.id != Playlist.favoritesID else { return false }
        return userPlaylists.playlists.contains { $0.id == playlist.id }
    }
}
