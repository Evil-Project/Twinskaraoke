import SwiftUI
struct TVAddToPlaylistSheet: View {
    let song: Song

    @Environment(\.dismiss) private var dismiss
    private let manager = TVUserPlaylistsManager.shared

    @State private var addingPlaylistID: String?
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundStyle(Color.appAccent)
                }

                content
            }
            .frame(minWidth: 900, maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 80)
            .padding(.vertical, 44)
        }
        .onAppear { manager.loadIfNeeded() }
        .sheet(isPresented: $isCreating) {
            TVCreatePlaylistSheet()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to Playlist")
                .font(.system(size: 44, weight: .bold))
            Text(song.title)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !manager.isSignedIn {
            message(String(localized: "Sign in from the Account tab to add songs to your playlists."))
        } else if manager.playlists.isEmpty && manager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let loadError = manager.loadError, manager.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                message(loadError)
                TVActionButton(title: String(localized: "Retry"), systemImage: "arrow.clockwise") {
                    manager.load()
                }
            }
        } else if manager.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                message(String(localized: "You don’t have any playlists yet."))
                TVActionButton(title: String(localized: "New Playlist"), systemImage: "plus") {
                    isCreating = true
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(manager.playlists) { playlist in
                    row(for: playlist)
                }
            }
        }
    }

    private func row(for playlist: UserPlaylist) -> some View {
        let display = playlist.asPlaylist()
        return Button {
            add(to: playlist)
        } label: {
            HStack(spacing: 20) {
                TVArtwork(url: display.rowImageURL, cornerRadius: 8)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(display.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(display.songCountText)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(0.6))
                }

                Spacer(minLength: 12)

                if addingPlaylistID == playlist.id {
                    ProgressView()
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(addingPlaylistID == playlist.id)
        .accessibilityLabel(display.name)
        .accessibilityValue(display.songCountText)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 900, alignment: .leading)
    }

    private func add(to playlist: UserPlaylist) {
        guard addingPlaylistID == nil else { return }
        addingPlaylistID = playlist.id
        errorMessage = nil

        Task {
            let added = await manager.addSong(song.id, to: playlist.id)
            addingPlaylistID = nil
            if added {
                dismiss()
            } else {
                let name = playlist.asPlaylist().name
                errorMessage = String(localized: "Couldn’t add the song to “\(name)”. Try again.")
            }
        }
    }
}
struct TVAddToPlaylistMenuButton: View {
    let song: Song
    @Binding var selection: Song?

    var body: some View {
        Button {
            selection = song
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
    }
}

extension View {
    func addToPlaylistSheet(song: Binding<Song?>) -> some View {
        sheet(item: song) { song in
            TVAddToPlaylistSheet(song: song)
        }
    }
}
