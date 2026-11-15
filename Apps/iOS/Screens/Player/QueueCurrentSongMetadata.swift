import SwiftUI

struct QueueCurrentSongMetadata: View {
    let title: String
    let artist: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Now Playing")
                .font(AM.Font.badge)
                .foregroundStyle(Color.appAccent)
                .textCase(.uppercase)
            Text(title)
                .font(AM.Font.groupHeader)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(artist)
                .font(AM.Font.rowSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
