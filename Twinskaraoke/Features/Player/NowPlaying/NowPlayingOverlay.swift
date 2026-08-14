import SwiftUI

/// Presents the full-screen player above the whole app, and owns the gesture
/// that dismisses it.
///
/// It is an overlay rather than a `fullScreenCover` because the dismissal has
/// to be finger-tracked, and a modal presentation's transition is not ours to
/// drive. It is a sibling of the app shell rather than a child of any screen
/// because it has to cover the tab bar.
///
/// The gesture is attached with plain `.gesture(_:)`, and that is a deliberate
/// choice rather than an incidental one. SwiftUI resolves a child's gesture
/// before its container's, so the scrubber in `AppleMusicProgressBar`, the
/// volume row, and the lyrics and queue scroll views all keep their own drags,
/// while every other point on the player belongs to this. `simultaneousGesture`
/// would let this run *alongside* the scrubber and drag the player while
/// someone is trying to seek; `highPriorityGesture` would take the scrubber
/// away entirely.
///
/// That single line is what the library this replaces spent its gesture layer
/// trying to achieve. Because it was retrofitting onto view trees it did not
/// own, it had to negotiate: declare a failure requirement against every other
/// recognizer in the content, then graft its own handler onto whichever of
/// those recognizers it could find at open-time. When the graft missed — and
/// against SwiftUI's recognizers it always missed, because the handler
/// string-matched for `UIScrollView` — both paths went dead and the player
/// simply stopped responding to downward drags. We own this view tree, so
/// there is nothing to negotiate with.
struct NowPlayingOverlay: View {
    @Environment(\.appReduceMotion) private var reduceMotion

    private let presentation = NowPlayingPresentation.shared
    private let snapshot = NowPlayingSnapshotState.shared

    /// Upward give at the top of the travel, kept local because it is purely
    /// cosmetic — nothing outside this view has any use for "the player is
    /// 12pt higher than open".
    @State private var overshoot: CGFloat = 0

    /// Whether the current drag has been claimed as a vertical one. Judged once,
    /// on the opening movement, so a drag that starts vertical and wanders
    /// sideways keeps working.
    @State private var isDraggingVertically = false

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            // Mounted for as long as there is a song, not just while open, and
            // parked off the bottom of the screen the rest of the time. The
            // player owns a lot of state that should survive being closed —
            // whether lyrics are showing, two `LyricsViewModel`s and their
            // fetches, the queue sheet. Building it on open instead would
            // reset all of that and refetch lyrics every time, which is not
            // what the popup it replaces did: that created its content view
            // controller as soon as the bar appeared and kept it.
            if snapshot.hasCurrentSong {
                FullScreenPlayerView()
                    .environment(AudioPlayerManager.shared)
                    .frame(width: proxy.size.width, height: height)
                    .offset(y: offset(height: height))
                    .gesture(dismissDrag(height: height))
            }
            // Above the player, because for most of the transition the player
            // is still on its way up and the artwork has to be seen crossing
            // the gap between the two.
            artworkMorph
        }
        // Outside the reader, so the reader's region is the whole window: the
        // player draws under the status bar and the home indicator, and its own
        // `GeometryReader` still reports the real insets to lay its content out
        // against. `FullScreenPlayerView` pads by `safeAreaInsets` internally
        // and would collide with both if it were handed a safe-area-sized frame.
        .ignoresSafeArea()
        // Nothing below can be reached while the player is up, and nothing here
        // may intercept a touch while it is down.
        .allowsHitTesting(presentation.isPresenting)
        // Off-screen is not hidden as far as VoiceOver is concerned: a parked
        // player is still in the accessibility tree, and would otherwise sit
        // there as a screenful of focusable controls behind the app.
        .accessibilityHidden(!presentation.isPresenting)
        .onChange(of: reduceMotion, initial: true) { _, isReduced in
            presentation.prefersReducedMotion = isReduced
        }
        // The player has nothing to show once the song is gone — playback
        // cleared, queue emptied. Animating it away would be animating an
        // empty screen, since `FullScreenPlayerView` renders nothing without a
        // current song.
        .onChange(of: snapshot.hasCurrentSong) { _, hasSong in
            if !hasSong {
                presentation.dismissImmediately()
            }
        }
    }

    // MARK: - The artwork in flight

    @ViewBuilder
    private var artworkMorph: some View {
        if presentation.isMorphingArtwork,
           let image = snapshot.artwork,
           let from = presentation.barArtworkFrame,
           let to = presentation.playerArtworkFrame {
            ArtworkMorphLayer(
                image: image,
                from: from,
                to: to,
                progress: presentation.progress,
                targetScale: snapshot.isPlaying ? 1 : PlayerArtworkView.pausedScale
            )
        }
    }

    // MARK: - Geometry

    private func offset(height: CGFloat) -> CGFloat {
        (1 - presentation.progress) * height + overshoot
    }

    // MARK: - The dismissal gesture

    private func dismissDrag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // A sideways drag is somebody else's — most likely a swipe
                // across the artwork. Claiming it here would make the player
                // twitch downward on every horizontal gesture.
                if !isDraggingVertically {
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    isDraggingVertically = true
                }

                let travel = PlayerDismissMetrics.dragOffset(
                    forTranslation: value.translation.height, height: height
                )
                if travel >= 0 {
                    overshoot = 0
                    presentation.drag(to: PlayerDismissMetrics.progress(forOffset: travel, height: height))
                } else {
                    // Already fully open; the give is all there is above it.
                    overshoot = travel
                    presentation.drag(to: 1)
                }
            }
            .onEnded { value in
                guard isDraggingVertically else { return }
                isDraggingVertically = false

                let dismissing = PlayerDismissMetrics.shouldDismiss(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height,
                    height: height
                )
                withOptionalAnimation(reduceMotion ? nil : AppMotion.gentle) {
                    overshoot = 0
                }
                presentation.endDrag(dismissing: dismissing)
            }
    }
}
