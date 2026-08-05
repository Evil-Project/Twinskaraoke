import SwiftUI

/// Browse public playlists.
///
/// These used to be poured into the sidebar's Playlists section as a signed-out
/// fallback, which pushed everything else out of reach. A grid in the detail
/// pane is where a hundred playlists actually belong.
struct LibraryView: View {
    @State private var model = MacLibraryViewModel()
    @Binding var selection: MacDestination?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        Group {
            if model.isLoading && model.playlists.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, model.playlists.isEmpty {
                StateMessage(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't load the library",
                    subtitle: error
                )
            } else if model.playlists.isEmpty {
                StateMessage(systemImage: "books.vertical", title: "Nothing here yet")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(model.playlists) { playlist in
                            PlaylistCard(playlist: playlist) {
                                selection = .playlist(id: playlist.id, name: playlist.name)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .task { await model.loadIfNeeded() }
    }
}

struct PlaylistCard: View {
    let playlist: Playlist
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        // A Button rather than onTapGesture: tap gestures are pointer-only, so
        // the cards were unreachable by keyboard.
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    SongArtwork(url: playlist.imageURL, size: 150, cornerRadius: 8)
                    if isHovering {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.35))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 150, height: 150)

                Text(playlist.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(playlist.songCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(playlist.name)
        .accessibilityLabel("\(playlist.name), \(playlist.songCountText)")
    }
}
