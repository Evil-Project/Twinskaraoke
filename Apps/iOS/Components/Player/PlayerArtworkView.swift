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
            // The morph target, reported from the artwork itself rather than
            // from the body: the body carries `.frame(maxWidth: .infinity)`, so
            // its frame is the full column width, and `size` is often smaller —
            // the flying artwork was landing at the column's width and only
            // snapping down to the real one when the morph ended. Reported from
            // here it covers all five call sites (compact, both iPad layouts,
            // radio), and only one is ever on screen.
            //
            // Inside the `.id(song.id)` below, so every song's artwork, and
            // every instance, reports under its own owner.
            .modifier(PlayerArtworkFrameReporter())
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
            .id(song.id)
            .scaleEffect(artworkScale)
            .amShadow(audioManager.isPlaying ? AM.Shadow.heroPlaying : AM.Shadow.heroIdle)
            .modifier(ThemedArtworkGlow(isPlaying: audioManager.isPlaying))
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

/// A website theme rings the artwork in its primary, as the site does its
/// covers (`.song-cover-placeholder`: `0 0 40px primary/0.3`, and `/0.2` on
/// `.playlist-main-cover`): brighter while playing, softer while paused.
/// Without a theme it adds nothing, not even an empty shadow pass.
private struct ThemedArtworkGlow: ViewModifier {
    let isPlaying: Bool

    func body(content: Content) -> some View {
        if let primary = AppThemeStore.shared.palette?.primary {
            content.shadow(color: primary.opacity(isPlaying ? 0.3 : 0.2), radius: 20)
        } else {
            content
        }
    }
}

/// Reports the artwork's frame as the morph target under an owner unique to
/// this view instance; see `NowPlayingPresentation.FrameReports`.
private struct PlayerArtworkFrameReporter: ViewModifier {
    @State private var owner = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                // The expanded destination must stay fixed while the entire
                // player moves. A global frame includes its animated offset.
                proxy.frame(in: .named("FullPlayerSurface"))
            } action: { frame in
                NowPlayingPresentation.shared.reportPlayerArtworkFrame(frame, owner: owner)
            }
            // The artwork is not always on screen — the lyrics surface
            // replaces it — and a frame left behind after it goes would aim
            // the morph at somewhere the artwork no longer is.
            .onDisappear {
                NowPlayingPresentation.shared.removePlayerArtworkFrame(owner: owner)
            }
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
