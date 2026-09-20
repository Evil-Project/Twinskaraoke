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
                artwork
                    .contentShape(.rect)
                    .onTapGesture {
                        AppHaptic.selection.play()
                        onTap()
                    }
            } else {
                artwork
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(NowPlayingPresentation.shared.isMorphingArtwork ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("PlayerArtwork")
        .accessibilityLabel("\(song.title) artwork")
        .accessibilityHint(onTap == nil ? "Album artwork." : "Opens full-screen artwork.")
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityActivation(onTap)
    }

    private var artwork: some View {
        ZStack {
            RemoteArtworkImage(
                url: audioManager.displayImageURL(for: song, variant: .card),
                cornerRadius: AM.Radius.hero,
                contentMode: .fill,
                lowResURL: audioManager.displayImageURL(for: song, variant: .thumbnail)
            )
            .overlay {
                #if DEBUG
                if PlayerClosingTestArtwork.enabled {
                    Image(uiImage: PlayerClosingTestArtwork.image).resizable().scaledToFill()
                }
                #endif
            }
            .frame(width: size, height: size)
            .onGeometryChange(for: CGRect.self) { proxy in
                // The expanded destination must stay fixed while the entire
                // player moves. A global frame includes its animated offset.
                proxy.frame(in: .named("FullPlayerSurface"))
            } action: { frame in
                NowPlayingPresentation.shared.reportPlayerArtworkFrame(frame)
            }
            .onDisappear {
                NowPlayingPresentation.shared.reportPlayerArtworkFrame(nil)
            }
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
    private static let pausedScale: CGFloat = 0.88

    private var artworkScale: CGFloat {
        audioManager.isPlaying ? 1.0 : Self.pausedScale
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

private extension View {
    @ViewBuilder
    func accessibilityActivation(_ action: (() -> Void)?) -> some View {
        if let action {
            accessibilityAction { action() }
        } else {
            self
        }
    }
}
