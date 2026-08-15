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
                    // A tap gesture rather than a `Button`, and the difference
                    // is the whole point. A SwiftUI button fires on touch-up
                    // whenever the touch is still inside its bounds; it has no
                    // notion of the finger having travelled. This is the largest
                    // target on the player, so a drag down that began and ended
                    // on the artwork stayed in bounds and opened the full-screen
                    // cover art instead of dismissing the player. Drags long
                    // enough to leave the artwork behaved, which is what made it
                    // intermittent.
                    //
                    // `TapGesture` fails once the touch moves past its
                    // tolerance, so the drag reaches `NowPlayingOverlay` — child
                    // gestures resolve first, and a failed one yields. A
                    // deliberate tap is unaffected; both halves are covered by
                    // `testDraggingDownFromTheArtworkDoesNotOpenTheCoverArt` and
                    // `testTappingTheArtworkOpensTheCoverArt`.
                    //
                    // The cost is the press-in scale and dim that
                    // `PressableButtonStyle` gave this. No gesture reports a
                    // press state without claiming the touch, and claiming it is
                    // exactly what must not happen here; the selection haptic
                    // still marks the moment.
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
        // Explicit now that this is no longer a `Button`, so VoiceOver still
        // announces it as one and offers the action below.
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
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
            // The morph target, reported from the artwork itself rather than
            // from the body: the body carries `.frame(maxWidth: .infinity)`, so
            // its frame is the full column width, and `size` is often smaller —
            // the flying artwork was landing at the column's width and only
            // snapping down to the real one when the morph ended. Reported from
            // here it covers all five call sites (compact, both iPad layouts,
            // radio), and only one is ever on screen.
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                NowPlayingPresentation.shared.reportPlayerArtworkFrame(frame)
            }
            // The artwork is not always on screen — the lyrics surface replaces
            // it — and a frame left behind after it goes would aim the morph at
            // somewhere the artwork no longer is.
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

    /// How far the artwork shrinks while paused.
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
