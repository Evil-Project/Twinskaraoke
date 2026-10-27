import SwiftUI

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
