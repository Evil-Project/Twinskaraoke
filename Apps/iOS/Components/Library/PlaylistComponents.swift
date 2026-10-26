import SwiftUI

// MARK: - LibraryActionButtonLabel

struct LibraryActionButtonLabel: View {
    let symbol: String
    let text: String
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
            Text(text).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(Color.appAccent)
        .background(Color.appControlInactiveFill, in: shape)
        .shadow(color: Color.appShadow.opacity(0.18), radius: 5, x: 0, y: 2)
        .contentShape(shape)
    }
}

// MARK: - PlaylistActionsMenuItems

struct PlaylistActionsMenuItems: View {
    let playlist: Playlist
    let songs: [Song]
    /// False for a set that has no page of its own to open, such as Random
    /// Songs, which is regenerated on every refresh.
    var allowsPinning = true
    private let savedStore = SavedPlaylistsStore.shared
    private let pins = PinnedPlaylistsStore.shared
    private let downloads = DownloadManager.shared

    private var isSaved: Bool {
        savedStore.isSaved(playlist)
    }

    private var canSaveToLibrary: Bool {
        !playlist.isFavorites && !playlist.isPersonal
    }

    /// Favourite Songs only exists for a signed-in account.
    private var canPin: Bool {
        allowsPinning && (!playlist.isFavorites || FavoritesManager.shared.isAvailable)
    }

    var body: some View {
        let state = downloads.status(for: songs)
        let pendingSongs = state.pendingSongs
        let inFlightCount = state.inFlightCount
        let pendingCount = pendingSongs.count
        let allDownloaded = !songs.isEmpty
            && pendingCount == 0
            && inFlightCount == 0

        if !songs.isEmpty {
            Button {
                AppHaptic.selection.play()
                if let first = songs.first {
                    PlaylistPlayback.playInOrder(first, from: playlist, context: songs)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                AppHaptic.selection.play()
                PlaylistPlayback.playShuffled(from: playlist, songs: songs)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }

            Divider()
        }

        if canSaveToLibrary {
            Button {
                AppHaptic.selection.play()
                SavedPlaylistsStore.shared.toggle(playlist)
            } label: {
                if isSaved {
                    Label("Remove from Library", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Add to Library", systemImage: "plus.circle")
                }
            }
        }

        if canPin {
            pinButton
        }

        if !songs.isEmpty {
            if inFlightCount > 0 {
                Label("Downloading \(inFlightCount)…", systemImage: "arrow.down.circle")
                Button(role: .destructive) {
                    downloads.cancel(songs: songs)
                    AppHaptic.dismiss.play()
                } label: {
                    Label("Cancel Playlist Download", systemImage: "xmark.circle")
                }
            } else if allDownloaded {
                Button(role: .destructive) {
                    AppHaptic.warning.play()
                    downloads.remove(songIDs: songs.map(\.id))
                } label: {
                    Label("Remove Downloads", systemImage: "trash")
                }
            } else {
                Button {
                    AppHaptic.success.play()
                    downloads.download(songs: pendingSongs)
                } label: {
                    let label = pendingCount < songs.count ? String(localized: "Download Remaining") : String(localized: "Download")
                    Label(label, systemImage: "arrow.down.circle")
                }
            }
        }
    }

    @ViewBuilder private var pinButton: some View {
        if pins.isPinned(playlist) {
            Button {
                AppHaptic.selection.play()
                pins.unpin(playlist)
            } label: {
                Label("Unpin Playlist", systemImage: "pin.slash")
            }
        } else if pins.isFull {
            // Shown disabled rather than hidden, with the reason as the
            // subtitle, so a full set of pins doesn't read as a missing feature.
            // The subtitle has to be a second view of the button's own label:
            // nested inside the Label's title, the menu drops it.
            Button {} label: {
                Label("Pin Playlist", systemImage: "pin")
                Text("Pins are full. Unpin one first.")
            }
            .disabled(true)
        } else {
            Button {
                AppHaptic.selection.play()
                pins.pin(playlist)
            } label: {
                Label("Pin Playlist", systemImage: "pin")
            }
        }
    }
}

// MARK: - PlaylistRow

struct PlaylistRow: View {
    let song: Song

    var showsArtwork = true
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin

    var body: some View {
        SongRow(song: song, size: .regular, showsArtwork: showsArtwork)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
    }
}

// MARK: - PlaylistSongRemoval

struct PlaylistSongRemovalContext {
    let playlistID: String
    let playlistName: String
    let remove: (Song) -> Void
}

private struct PlaylistSongRemovalKey: EnvironmentKey {
    static var defaultValue: PlaylistSongRemovalContext? { nil }
}

extension EnvironmentValues {
    var playlistSongRemoval: PlaylistSongRemovalContext? {
        get { self[PlaylistSongRemovalKey.self] }
        set { self[PlaylistSongRemovalKey.self] = newValue }
    }
}
