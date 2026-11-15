import SwiftUI

struct QueueCurrentSongLabel: View {
    let artworkURL: URL?
    let thumbnailURL: URL?
    let title: String
    let artist: String
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            RemoteArtworkImage(
                url: artworkURL,
                cornerRadius: AM.Radius.thumb,
                lowResURL: thumbnailURL
            )
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous))
            QueueCurrentSongMetadata(title: title, artist: artist)
            Spacer()

            EqualizerBars(isAnimating: isPlaying, pausesWhileScrolling: false)
                .frame(width: 16, height: 16)
                .foregroundStyle(Color.appAccent)
        }
    }
}
