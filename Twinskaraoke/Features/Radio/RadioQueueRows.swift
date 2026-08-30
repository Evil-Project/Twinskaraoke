import SwiftUI

struct RadioQueueTrackRow: View {
    let song: RadioNowPlaying.SongInfo
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            RadioQueueArtwork(song: song, cornerRadius: AM.Radius.thumb)
                .frame(width: 54, height: 54)
                .overlay(alignment: .topLeading) {
                    if isCurrent {
                        Text("LIVE")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.appAccent))
                            .padding(5)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(isCurrent ? Color.appAccent : .primary)
                    .lineLimit(1)
                Text(song.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isCurrent {
                    Text(isPlaying ? "On air now" : "Live station")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isCurrent {
                EqualizerBars(isAnimating: false)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.appAccent)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

struct RadioQueuePreview: View {
    let song: RadioNowPlaying.SongInfo
    let isCurrent: Bool

    var body: some View {
        ContextPreviewCard {
            RadioQueueArtwork(song: song, cornerRadius: 10)
                .frame(width: 220, height: 220)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if isCurrent {
                    Text("Live Now")
                        .font(.caption.bold())
                        .foregroundStyle(Color.appAccent)
                        .textCase(.uppercase)
                }
                Text(song.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
