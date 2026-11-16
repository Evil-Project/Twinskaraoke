import SwiftUI

struct BandleGuessSuggestions: View {
    let songs: [BandleGuessSong]
    let onSelect: (BandleGuessSong) -> Void

    var body: some View {
        if songs.isEmpty {
            ContentUnavailableView(
                String(localized: "No matching songs"),
                systemImage: "magnifyingglass",
                description: Text(String(localized: "Try a different song title or artist."))
            )
        } else {
            VStack(spacing: 0) {
                ForEach(songs) { song in
                    VStack(spacing: 0) {
                        Button {
                            onSelect(song)
                        } label: {
                            VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                                Text(song.displayName)
                                    .font(AM.Font.rowTitle)
                                    .foregroundStyle(.primary)
                                if let artists = song.coverArtists ?? song.originalArtists {
                                    Text(artists)
                                        .font(AM.Font.rowCompactSubtitle)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.vertical, AM.Spacing.s)
                            .padding(.horizontal, AM.Spacing.m)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Bandle.Song.\(song.id)")
                        Divider()
                    }
                }
            }
            .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
        }
    }
}
