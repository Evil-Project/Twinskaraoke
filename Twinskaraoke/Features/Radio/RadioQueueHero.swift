import SwiftUI

struct RadioQueueHero: View {
    let song: RadioNowPlaying.SongInfo
    let stationName: String
    let listenerCount: Int?
    let lastUpdated: Date?
    let isPlaying: Bool
    let reduceMotion: Bool
    let onPlayPause: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack(alignment: .bottomLeading) {
                RadioQueueArtwork(song: song, cornerRadius: 10)
                    .frame(width: 72, height: 72)
                    .amShadow(isPlaying ? AM.Shadow.heroPlaying : AM.Shadow.heroIdle)

                RadioQueueLivePill(isPlaying: isPlaying, reduceMotion: reduceMotion)
                    .padding(5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stationName)
                    .font(.caption.bold())
                    .foregroundStyle(Color.appAccent)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(song.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                RadioQueueHeroStatusRow(
                    listenerCount: listenerCount,
                    lastUpdated: lastUpdated,
                    isPlaying: isPlaying
                )
            }

            Spacer(minLength: 4)

            Button {
                AppHaptic.commit.play()
                onPlayPause()
            } label: {
                Label(isPlaying ? "Pause live station" : "Play live station", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .font(.headline.bold())
                    .foregroundStyle(Color.appControlActiveForeground)
                    .frame(width: 44, height: 44)
                    .background(Color.appControlActiveFill, in: Circle())
                    .offset(x: isPlaying ? 0 : 1)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.76))
            .accessibilityLabel(isPlaying ? "Pause live station" : "Play live station")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.appDivider.opacity(0.8), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPlaying ? "Live now, on air" : "Live now")
        .accessibilityValue("\(song.displayTitle), \(song.displayArtist)")
    }
}

private struct RadioQueueLivePill: View {
    let isPlaying: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                if isPlaying, !reduceMotion {
                    Circle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 11, height: 11)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 11, height: 11)

            Text(isPlaying ? "ON AIR" : "LIVE")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.appAccent))
        .accessibilityHidden(true)
    }
}

private struct RadioQueueHeroStatusRow: View {
    let listenerCount: Int?
    let lastUpdated: Date?
    let isPlaying: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                statusItems
            }
            VStack(alignment: .leading, spacing: 2) {
                statusItems
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusItems: some View {
        Label(isPlaying ? "Broadcasting" : "Ready", systemImage: isPlaying ? "waveform" : "antenna.radiowaves.left.and.right")
            .lineLimit(1)
        if let listenerCount {
            Label(listenerCount == 1 ? "1 listener" : "\(listenerCount) listeners", systemImage: "person.2.fill")
                .lineLimit(1)
        }
        if let lastUpdated {
            Label("Updated \(lastUpdated.formatted(.relative(presentation: .named)))", systemImage: "clock")
                .lineLimit(1)
        }
    }
}
