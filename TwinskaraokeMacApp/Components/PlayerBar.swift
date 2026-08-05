import SwiftUI

/// Persistent transport strip pinned to the bottom of the window.
///
/// The Mac idiom for a media app, and the deliberate replacement for the iOS
/// LNPopup miniplayer — that library is iOS/Catalyst-only, and a drag-up popup
/// would be wrong here regardless.
struct PlayerBar: View {
    @Environment(MacAudioManager.self) private var audio
    @State private var scrubTime: Double?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                nowPlaying
                Spacer(minLength: 12)
                transport
                Spacer(minLength: 12)
                volume
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    // MARK: - Sections

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            SongArtwork(url: audio.currentSong?.thumbnailURL, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(audio.currentSong?.displayTitle ?? "Nothing Playing")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(audio.currentSong?.displayArtist ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 140, alignment: .leading)
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var transport: some View {
        VStack(spacing: 4) {
            HStack(spacing: 18) {
                Button { audio.playPrevious() } label: {
                    Image(systemName: "backward.fill")
                }
                .disabled(!audio.canPlayPrevious)

                Button { audio.togglePlayPause() } label: {
                    Image(systemName: playPauseIcon)
                        .font(.system(size: 22))
                }
                .disabled(audio.currentSong == nil)

                Button { audio.playNext() } label: {
                    Image(systemName: "forward.fill")
                }
                .disabled(!audio.canPlayNext)

                Button { audio.cycleMode() } label: {
                    Image(systemName: audio.playbackMode.iconName)
                }
                .help(audio.playbackMode.label)
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))

            scrubber
        }
        .frame(maxWidth: 460)
    }

    private var scrubber: some View {
        HStack(spacing: 8) {
            Text(Self.timeText(displayedTime))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(audio.duration, 1),
                onEditingChanged: { editing in
                    // Commit on release only: seeking on every drag frame makes
                    // AVPlayer stutter.
                    guard !editing, let target = scrubTime else { return }
                    audio.seek(to: target)
                    scrubTime = nil
                }
            )
            .controlSize(.mini)
            .disabled(audio.duration <= 0)

            Text(Self.timeText(audio.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }
    }

    private var volume: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Slider(value: Bindable(audio).volume, in: 0...1)
                .controlSize(.mini)
                .frame(width: 80)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 160, alignment: .trailing)
    }

    // MARK: - Helpers

    private var displayedTime: Double {
        scrubTime ?? audio.currentTime
    }

    private var playPauseIcon: String {
        if audio.isLoading { return "hourglass" }
        return audio.isPlaying ? "pause.circle.fill" : "play.circle.fill"
    }

    private static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
