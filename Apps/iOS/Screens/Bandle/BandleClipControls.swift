import SwiftUI

struct BandleClipControls: View {
    let clip: BandleAudioClip?
    let isLoading: Bool
    @Bindable var player: BandleClipPlayer

    var body: some View {
        VStack(spacing: AM.Spacing.m) {
            HStack(spacing: AM.Spacing.l) {
                Button(
                    player.isPlaying ? String(localized: "Pause clip") : String(localized: "Play clip"),
                    systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                    action: togglePlayback
                )
                .buttonStyle(.borderedProminent)
                .disabled(clip?.playableURL == nil || isLoading)
                .accessibilityIdentifier("Bandle.TogglePlayback")

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: AM.Spacing.xs) {
                        Slider(value: $player.playbackProgress, onEditingChanged: scrubbingChanged)
                            .disabled(clip?.playableURL == nil)
                            .accessibilityLabel(String(localized: "Clip position"))

                        HStack {
                            Text(Duration.seconds(player.currentTime).formatted(.time(pattern: .minuteSecond)))
                            Spacer()
                            Text(Duration.seconds(clip?.clipLength ?? 0).formatted(.time(pattern: .minuteSecond)))
                        }
                        .font(AM.Font.timecode)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let clip {
                Text(String(localized: "\(clip.clipLength ?? 0)-second clip · Attempt \(clip.attemptNumber ?? 1) of 6"))
                    .font(AM.Font.rowCompactSubtitle)
                    .foregroundStyle(.secondary)
                if let effect = clip.effect, effect != .none {
                    Label(effect.title, systemImage: "wand.and.stars")
                        .font(AM.Font.rowCompactSubtitle)
                        .foregroundStyle(Color.appAccent)
                }
            } else {
                Text(String(localized: "Choose an unlocked attempt to load its clip."))
                    .font(AM.Font.rowCompactSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AM.Spacing.l)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
    }

    private func scrubbingChanged(_ isEditing: Bool) {
        if isEditing { player.pause() }
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }
}
