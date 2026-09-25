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
                    PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
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
    }
}
