import SwiftUI

/// Pinned playlists at the top of Library, drawn the way Apple Music draws
/// its pins: artwork-only rounded squares, three to a row, above the category
/// list. The name is in the context-menu preview and the accessibility label.
struct LibraryPinnedPlaylists: View {
    let playlists: [Playlist]
    /// LibraryView's, so a pin zooms into the playlist it opens.
    let zoomNamespace: Namespace.ID
    @Environment(\.appReduceMotion) private var reduceMotion
    private let pins = PinnedPlaylistsStore.shared
    /// Songs for pins that arrive without them: a stored pin, or a playlist
    /// the library list returns without its songs. A context menu is
    /// snapshotted when it opens, so without songs already in hand the pin's
    /// menu would have no Play, Shuffle or Download.
    @State private var loadedSongs: [String: [Song]] = [:]

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: AM.Spacing.m, alignment: .top),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: AM.Spacing.m) {
            ForEach(playlists) { playlist in
                // Prefixed: the Playlists grid pushed on top of Library uses
                // the bare playlist id as its zoom source in the same
                // namespace, and a duplicate would let a pin still mounted
                // underneath answer for that screen's transition.
                ZoomNavigationLink(id: "pin.\(playlist.id)", in: zoomNamespace) {
                    PlaylistDetailView(playlist: playlist)
                } label: {
                    PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.tile)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
                        // Artwork drawn on white otherwise loses its edge
                        // against the page, and the grid reads as gaps.
                        .overlay {
                            RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous)
                                .strokeBorder(Color.appDivider.opacity(0.7), lineWidth: 0.5)
                        }
                }
                .buttonStyle(PressableButtonStyle(haptic: .selection))
                .contextMenu {
                    PlaylistActionsMenuItems(playlist: playlist, songs: songs(for: playlist))
                } preview: {
                    PlaylistContextPreview(playlist: playlist)
                }
                .accessibilityLabel(playlist.name)
                .accessibilityHint("Shows playlist details.")
                .accessibilityAction(named: "Unpin Playlist") {
                    AppHaptic.selection.play()
                    pins.unpin(playlist)
                }
                .accessibilityIdentifier("LibraryPin.\(playlist.id)")
                .transition(
                    reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity)
                )
            }
        }
        .animation(reduceMotion ? nil : AppMotion.snap, value: playlists.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned")
        .accessibilityIdentifier("Library.Pinned")
        // Runs each time Library appears, so the menu doesn't play a list
        // that changed since. The API caches playlist details for a minute,
        // which keeps a repeat cheap and warms the pin's own detail screen.
        .task(id: playlists.map(\.id)) {
            await loadMissingSongs()
        }
    }

    private func songs(for playlist: Playlist) -> [Song] {
        if let songs = playlist.songListDTOs, !songs.isEmpty {
            return songs
        }
        return loadedSongs[playlist.id] ?? []
    }

    private func loadMissingSongs() async {
        let missing = playlists
            .filter { $0.songListDTOs?.isEmpty ?? true }
            .map(\.id)
        guard !missing.isEmpty else { return }
        await withTaskGroup(of: (String, [Song]?).self) { group in
            for id in missing {
                group.addTask {
                    (id, try? await KaraokeAPIClient.playlistSongs(id: id))
                }
            }
            for await (id, songs) in group {
                guard !Task.isCancelled else { return }
                // A failed load keeps what an earlier visit found.
                if let songs {
                    loadedSongs[id] = songs
                }
            }
        }
    }
}
