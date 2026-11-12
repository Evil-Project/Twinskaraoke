import SwiftUI

struct SongActionsMenuItems: View {
    let song: Song
    let onAddToPlaylist: () -> Void
    private let favorites = FavoritesManager.shared
    // Non-nil only inside an editable playlist the user owns; see
    // PlaylistSongRemoval.swift.
    @Environment(\.playlistSongRemoval) private var playlistRemoval
    // Non-nil only on the Uploaded screen; see UploadedSongMenuActions.swift.
    @Environment(\.uploadedSongMenuActions) private var uploadActions

    init(song: Song, onAddToPlaylist: @escaping () -> Void) {
        self.song = song
        self.onAddToPlaylist = onAddToPlaylist
    }

    // Download state is read here, in `body`, and not in `init`. Every row's
    // menu and context menu builds one of these while the *row's* body runs,
    // so a read in `init` subscribed the whole row to `downloadedIDs` and
    // `inProgress`: each download that started or finished redrew every
    // visible song row, which `SongDownloadRowState` exists to prevent.
    var body: some View {
        let downloads = DownloadManager.shared
        let isDownloaded = downloads.isDownloaded(song.id)
        let isDownloading = downloads.isDownloading(song.id)
        Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.playNext(song: song)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.playLast(song: song)
        } label: {
            Label("Play Last", systemImage: "text.append")
        }

        if UserPlaylistsManager.shared.isAvailable {
            Button {
                AppHaptic.selection.play()
                onAddToPlaylist()
            } label: {
                Label("Add to Playlist", systemImage: "plus.circle")
            }
        }

        // Also gated on the account: a playlist screen left on the stack
        // across a sign-out still supplies a removal closure that can no
        // longer write anything.
        if let playlistRemoval, UserPlaylistsManager.shared.isAvailable {
            Button(role: .destructive) {
                AppHaptic.warning.play()
                playlistRemoval.remove(song)
            } label: {
                Label("Remove from Playlist", systemImage: "minus.circle")
            }
        }

        if favorites.isAvailable {
            Button {
                let wasFavorite = favorites.isFavorite(song.id)
                favorites.toggle(songID: song.id)
                if wasFavorite {
                    AppHaptic.selection.play()
                } else {
                    AppHaptic.success.play()
                }
            } label: {
                if favorites.isFavorite(song.id) {
                    Label("Remove from Favorites", systemImage: "star.slash")
                } else {
                    Label("Favorite", systemImage: "star")
                }
            }
        }

        Divider()

        if isDownloaded {
            Button(role: .destructive) {
                AppHaptic.warning.play()
                DownloadManager.shared.remove(songID: song.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else if isDownloading {
            Button {
                AppHaptic.selection.play()
                DownloadManager.shared.cancel(songID: song.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else {
            Button {
                AppHaptic.success.play()
                DownloadManager.shared.download(song: song)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }

        if let pageURL = StorageHost.webPage(for: song) {
            Divider()
            ShareLink(item: pageURL, subject: Text(song.title), preview: SharePreview(song.title)) {
                Label("Share Song…", systemImage: "square.and.arrow.up")
            }
        }

        let uploadItems = UploadedSongMenuActions.items(offeredBy: uploadActions)
        if !uploadItems.isEmpty { Divider() }
        ForEach(uploadItems, id: \.self) { item in
            switch item {
            case .edit:
                Button {
                    uploadActions?.edit(song)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            case .delete:
                // Opens the confirmation; nothing is deleted from here.
                Button(role: .destructive) {
                    uploadActions?.delete(song)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
