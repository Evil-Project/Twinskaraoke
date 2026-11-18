import SwiftUI

/// The artist screen's "…" and artwork context menu.
///
/// Download state is read in `body`, not in `init`. The screen builds this
/// inside its `Menu` and `contextMenu` closures while its own body runs, so a
/// read in `init` subscribed the whole artist screen to every download that
/// started or finished, and re-ran the filters over every song each time.
/// See `SongActionsMenuItems` for the same fix on song rows.
struct ArtistActionsMenu: View {
    let songs: [Song]

    var body: some View {
        let status = DownloadManager.shared.status(for: songs)
        if songs.isEmpty {
            Text("No Songs")
        } else {
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

            if status.inFlightCount > 0 {
                Label("Downloading \(status.inFlightCount)...", systemImage: "arrow.down.circle")
            } else if status.pendingSongs.isEmpty {
                Button(role: .destructive) {
                    AppHaptic.dismiss.play()
                    DownloadManager.shared.remove(songIDs: songs.map(\.id))
                } label: {
                    Label("Remove Downloads", systemImage: "trash")
                }
            } else {
                Button {
                    AppHaptic.success.play()
                    DownloadManager.shared.download(songs: status.pendingSongs)
                } label: {
                    Label(downloadTitle(for: status), systemImage: "arrow.down.circle")
                }
            }
        }
    }

    private func downloadTitle(for status: SongCollectionDownloadStatus) -> String {
        let downloadedCount = songs.count - status.pendingSongs.count - status.inFlightCount
        return downloadedCount > 0 ? String(localized: "Download Remaining") : String(localized: "Download")
    }
}
