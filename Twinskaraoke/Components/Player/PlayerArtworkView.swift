import SwiftUI

struct PlayerArtworkView: View {
    @Environment(AudioPlayerManager.self) var audioManager
    @Environment(\.appReduceMotion) private var reduceMotion
    let song: Song
    let size: CGFloat
    var onTap: (() -> Void)?
    var body: some View {
        Group {
            if let onTap {
                Button {
                    AppHaptic.selection.play()
                    onTap()
                } label: {
                    artwork
                }
                .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.88, haptic: nil))
            } else {
                artwork
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(song.title) artwork")
        .accessibilityHint(onTap == nil ? "Album artwork." : "Opens full-screen artwork.")
        .accessibilityAction {
            onTap?()
        }
    }

    private var artwork: some View {
        ZStack {
            RemoteArtworkImage(
                url: audioManager.displayImageURL(for: song, variant: .card),
                cornerRadius: AM.Radius.hero,
                contentMode: .fill,
                lowResURL: audioManager.displayImageURL(for: song, variant: .thumbnail)
            )
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
            .id(song.id)
            .scaleEffect(artworkScale)
            .amShadow(audioManager.isPlaying ? AM.Shadow.heroPlaying : AM.Shadow.heroIdle)
            .animation(artworkPlaybackAnimation, value: audioManager.isPlaying)
            if audioManager.isBuffering {
                bufferingOverlay
                    .scaleEffect(artworkScale)
                    .transition(bufferingTransition)
            }
        }
        .animation(bufferingAnimation, value: audioManager.isBuffering)
    }

    private var bufferingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
                .fill(Color.appArtworkOverlay)
                .frame(width: size, height: size)
            ProgressView()
                .controlSize(.large)
        }
        .accessibilityHidden(true)
    }

    private var artworkScale: CGFloat {
        audioManager.isPlaying ? 1.0 : 0.88
    }

    private var artworkPlaybackAnimation: Animation? {
        reduceMotion ? nil : AppMotion.gentle
    }

    private var bufferingAnimation: Animation? {
        reduceMotion ? nil : AppMotion.snap
    }

    private var bufferingTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }
}
