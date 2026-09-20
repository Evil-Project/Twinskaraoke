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
        .onAppear {
            viewModel.fetchSongs()
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
            TVEmptyState(
                systemImage: "music.note.list",
                title: String(localized: "No songs yet"),
                message: String(localized: "Add songs to this playlist from the Twinskaraoke app on your phone, tablet, or the web.")
            )
            .frame(height: 400)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(Array(viewModel.songs.enumerated()), id: \.offset) { index, song in
                    row(for: song, at: index)
                }
            }
        }
    }
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
        .accessibilityActions {
            Button("Add to Playlist") {
                songToAdd = song
            }
            if canRemoveSongs {
                Button("Remove from Playlist") {
                    viewModel.removeSong(at: index)
                }
            }
        }
    }
    private var canRemoveSongs: Bool {
        guard playlist.id != Playlist.favoritesID else { return false }
        return userPlaylists.playlists.contains { $0.id == playlist.id }
    }
}
