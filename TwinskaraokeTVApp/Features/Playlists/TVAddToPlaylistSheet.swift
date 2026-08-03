import SwiftUI

/// Picker shown after choosing "Add to Playlist" on a song: one row per
/// playlist the user owns, tapping one adds the song and closes.
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
            // A tvOS sheet shrink-wraps its content, and one short playlist
            // name makes a card too narrow to read as a picker — the floor
            // keeps it the same width as the create sheet.
            .frame(minWidth: 900, maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 80)
            .padding(.vertical, 44)
        }
        .onAppear { manager.loadIfNeeded() }
        // Presented over this sheet so someone with no playlists yet isn't sent
        // back to the Playlists tab and made to start the song over.
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
            message("Sign in from the Account tab to add songs to your playlists.")
        } else if manager.playlists.isEmpty && manager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let loadError = manager.loadError, manager.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                message(loadError)
                TVActionButton(title: "Retry", systemImage: "arrow.clockwise") {
                    manager.load()
                }
            }
        } else if manager.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                message("You don’t have any playlists yet.")
                TVActionButton(title: "New Playlist", systemImage: "plus") {
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
                        // Derived from `.primary` for the reason `TVSongRow`
                        // documents: a plain tvOS button tints `.secondary`
                        // labels with the app accent.
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
        .disabled(addingPlaylistID != nil)
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
                errorMessage = "Couldn’t add the song to “\(playlist.name)”. Try again."
            }
        }
    }
}

/// The long-press menu item. Sets the binding the screen's single
/// `addToPlaylistSheet` presents from — one sheet per screen rather than one
/// per row, which would attach a presentation to every cell in a long list.
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
