import SwiftUI

struct PlaylistActionsMenuItems: View {
    let playlist: Playlist
    let songs: [Song]
    private let isSaved: Bool
    @ObservedObject private var downloads = DownloadManager.shared

    init(playlist: Playlist, songs: [Song]) {
        self.playlist = playlist
        self.songs = songs
        isSaved = SavedPlaylistsStore.shared.isSaved(playlist)
    }

    private var canSaveToLibrary: Bool {
        !playlist.isFavorites && !playlist.isPersonal
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
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                AppHaptic.selection.play()
                AudioPlayerManager.shared.playShuffled(from: songs)
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

        if !songs.isEmpty {
            if inFlightCount > 0 {
                Label("Downloading \(inFlightCount)…", systemImage: "arrow.down.circle")
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
                    let label = pendingCount < songs.count ? "Download Remaining" : "Download"
                    Label(label, systemImage: "arrow.down.circle")
                }
            }
        }
    }
}
