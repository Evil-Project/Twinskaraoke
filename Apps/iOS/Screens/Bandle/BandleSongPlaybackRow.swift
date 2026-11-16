import SwiftUI

/// Play/pause and progress for the revealed song, played in the card by the
/// Bandle clip player rather than the app's music player.
struct BandleSongPlaybackRow: View {
    let player: BandleClipPlayer

    var body: some View {
        HStack(spacing: AM.Spacing.m) {
            Button(
                player.isPlaying ? String(localized: "Pause song") : String(localized: "Play song"),
                systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                action: togglePlayback
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityIdentifier("Bandle.RevealedSong.TogglePlayback")

            VStack(spacing: AM.Spacing.xs) {
                ProgressView(value: player.progress)
                    .accessibilityHidden(true)
                HStack {
                    Text(Duration.seconds(player.currentTime).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text(Duration.seconds(player.duration).formatted(.time(pattern: .minuteSecond)))
                }
                .font(AM.Font.timecode)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }
}
