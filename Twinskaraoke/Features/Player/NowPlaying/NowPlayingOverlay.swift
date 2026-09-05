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

    /// The window's real safe-area insets, handed down from `PopupHostView`.
    ///
    /// They cannot be read from in here: this view ignores the safe area so the
    /// player can draw under the status bar and the home indicator, and a
    /// `GeometryReader` nested inside a region that has already ignored it
    /// reports zero. Measured on device — `size=402x874 safeTop=0 safeBottom=0`
    /// — which silently pushed `PlayerLayoutMetrics.contentHeight` from 781 to
    /// 874, past its 760pt `isCompactHeight` breakpoint, and made every font on
    /// the player a step too large.
    let safeAreaInsets: EdgeInsets

    private let presentation = NowPlayingPresentation.shared
    private let snapshot = NowPlayingSnapshotState.shared

    /// Upward give at the top of the travel, kept local because it is purely
    /// cosmetic — nothing outside this view has any use for "the player is
    /// 12pt higher than open".
    @State private var overshoot: CGFloat = 0
    @State private var canvasSize: CGSize = .zero
    @State private var closingTransition: PlayerClosingGeometry.Transition?
    @State private var closingPhase: Double = 0

    var body: some View {
        // Capture at the view boundary: the lazy GeometryReader content must
        // receive a new value on every pan update, not just on finger-up.
        let progress = presentation.progress
        return GeometryReader { proxy in
            let height = proxy.size.height
            let playerOffset = (1 - progress) * height + overshoot
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
                    .environment(\.playerSafeAreaInsets, safeAreaInsets)
                    .frame(width: proxy.size.width, height: height)
                    // Keep the opening morph in the same clipped surface as
                    // the background. Its path remains in window coordinates,
                    // converted to this moving surface before drawing.
                    .overlay {
                        artworkMorph(surfaceOffset: playerOffset)
                            .allowsHitTesting(false)
                    }
                    .background {
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-UITestPlayerTracking") {
                            PlayerTrackingProbe()
                        }
                        #endif
                    }
                    // Clipped before it is moved, because the player is parked
                    // just below the screen rather than unmounted, and
                    // `PlayerAmbientBackground` paints 96pt past every edge on
                    // purpose — it says so, and says the host clips the
                    // overflow. The popup's content view controller used to do
                    // that. Without it the parked player's backdrop bled up
                    // into the bottom of the screen as a band of ambient colour
                    // under the mini player. Clipping to the player's own frame
                    // costs nothing while it is open: that frame is the whole
                    // window, so the backdrop still covers every edge.
                    .clipped()
                    .coordinateSpace(name: "FullPlayerSurface")
                    .modifier(PlayerClosingSettlement(
                        transition: closingTransition, phase: closingPhase,
                        canvas: proxy.size, normalOffset: playerOffset,
                        image: snapshot.artwork
                    ))
                    .gesture(dismissDrag(height: height))
            }
        }
        // Outside the reader, so the reader's region is the whole window: the
        // player draws under the status bar and the home indicator, and its own
        // `GeometryReader` still reports the real insets to lay its content out
        // against. `FullScreenPlayerView` pads by `safeAreaInsets` internally
        // and would collide with both if it were handed a safe-area-sized frame.
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        // Keep the mini player's active opening gesture in its original host.
        // The overlay starts accepting touches after that gesture commits.
        .allowsHitTesting(presentation.isExpanded)
        // Off-screen is not hidden as far as VoiceOver is concerned: a parked
        // player is still in the accessibility tree, and would otherwise sit
        // there as a screenful of focusable controls behind the app.
        .accessibilityHidden(!presentation.isPresenting)
        // The player has nothing to show once the song is gone — playback
        // cleared, queue emptied. Animating it away would be animating an
        // empty screen, since `FullScreenPlayerView` renders nothing without a
        // current song.
        // The transition is performed here, in the tree that actually moves, so
        // it animates no matter which view asked for it — `MiniPlayerBar` lives
        // in the tab bar's accessory slot and its transactions do not reach us.
        //
        // Scoped to one update per transition rather than declared over the
        // subtree with `.animation(_:value:)`: that fired every frame of a drag
        // with a nil animation and interrupted the scrub bar's own fill
        // animation, which juddered while the player was dragged during
        // playback.
        .onChange(of: presentation.animationToken) { _, _ in
            withTransaction(Transaction(animation: nil)) {
                closingTransition = nil
                closingPhase = 0
            }
            guard presentation.isAnimatingTransition else { return }
            let token = presentation.animationToken
            // Release diagnostics: gesture acceptance alone cannot establish
            // whether the artwork settlement was selected. Record every gate
            // once per close, without logging URLs or doing per-frame work.
            if presentation.isClosingTransition {
                PlayerGestureTrace.record("landing request token=\(token) reduceMotion=\(reduceMotion) image=\(snapshot.artwork != nil) canvas=\(canvasSize) pill=\(String(describing: presentation.barFrame)) thumbnail=\(String(describing: presentation.barArtworkFrame)) artwork=\(String(describing: presentation.playerArtworkFrame)) releaseProgress=\(presentation.progress)")
            }
            if !reduceMotion, presentation.isClosingTransition,
               snapshot.artwork != nil, canvasSize.width > 0, canvasSize.height > 0,
               let pill = presentation.barFrame,
               let thumbnail = presentation.barArtworkFrame,
               let artwork = presentation.playerArtworkFrame {
                let offset = (1 - presentation.progress) * canvasSize.height + overshoot
                closingTransition = PlayerClosingGeometry.Transition(
                    canvas: canvasSize,
                    surface: CGRect(origin: CGPoint(x: 0, y: offset), size: canvasSize),
                    artwork: artwork.offsetBy(dx: 0, dy: offset),
                    pill: pill, thumbnail: thumbnail
                )
                presentation.prepareClosingSettlement()
            }
            if presentation.isClosingTransition {
                let missing = [
                    reduceMotion ? "reduceMotion" : nil,
                    snapshot.artwork == nil ? "image" : nil,
                    canvasSize.width <= 0 || canvasSize.height <= 0 ? "canvas" : nil,
                    presentation.barFrame == nil ? "pill" : nil,
                    presentation.barArtworkFrame == nil ? "thumbnail" : nil,
                    presentation.playerArtworkFrame == nil ? "artworkFrame" : nil
                ].compactMap { $0 }.joined(separator: ",")
                PlayerGestureTrace.record("landing selected token=\(token) mode=\(closingTransition == nil ? "slide" : "cover-curve") settling=\(presentation.isSettlingArtwork) skipped=\(missing.isEmpty ? "none" : missing)")
            }
            let animation: Animation? = reduceMotion ? nil : closingTransition != nil
                ? .linear(duration: PlayerClosingGeometry.duration)
                : .spring(response: 0.38, dampingFraction: 0.9)
            withAnimation(animation, completionCriteria: .removed) {
                presentation.applyAnimationTarget()
                closingPhase = 1
            } completion: {
                guard token == presentation.animationToken else { return }
                if closingTransition != nil {
                    PlayerGestureTrace.record("landing complete token=\(token) phase=\(closingPhase) image=\(snapshot.artwork != nil) settling=\(presentation.isSettlingArtwork)")
                }
                withTransaction(Transaction(animation: nil)) {
                    closingTransition = nil
                    closingPhase = 0
                }
                presentation.animationDidComplete(token: token)
            }
        }
        .onChange(of: snapshot.hasCurrentSong) { _, hasSong in
            if !hasSong {
                closingTransition = nil
                closingPhase = 0
                presentation.dismissImmediately()
            }
        }
    }

    // MARK: - The artwork in flight

    @ViewBuilder
    private func artworkMorph(surfaceOffset: CGFloat) -> some View {
        if presentation.isMorphingArtwork, !presentation.isSettlingArtwork,
           let image = snapshot.artwork,
           let from = presentation.barArtworkFrame,
           let to = presentation.playerArtworkFrame {
            ArtworkMorphLayer(
                image: image,
                from: from,
                to: to,
                progress: presentation.progress,
                surfaceOffset: surfaceOffset,
                // The same style the arriving artwork uses, so nothing changes
                // at the handover.
                shadow: snapshot.isPlaying ? AM.Shadow.heroPlaying : AM.Shadow.heroIdle
            )
        }
    }

    // MARK: - The dismissal gesture

    private func dismissDrag(height: CGFloat) -> PlayerPanGesture {
        PlayerPanGesture(canBegin: { presentation.isExpanded && !presentation.isDragging }) { translation in
            guard presentation.isExpanded else { return }
            withTransaction(Transaction(animation: nil)) {
                let travel = PlayerDismissMetrics.dragOffset(
                    forTranslation: translation, height: height
                )
                if travel >= 0 {
                    overshoot = 0
                    presentation.drag(to: PlayerDismissMetrics.progress(forOffset: travel, height: height), from: .fullPlayer)
                } else {
                    // Already fully open; the give is all there is above it.
                    overshoot = travel
                    presentation.drag(to: 1, from: .fullPlayer)
                }
            }
        } onEnded: { translation, projected in
            let dismissing = PlayerDismissMetrics.shouldDismiss(
                translation: translation,
                predictedTranslation: projected,
                height: height
            )
            withOptionalAnimation(reduceMotion ? nil : AppMotion.gentle) {
                overshoot = 0
            }
            presentation.endDrag(dismissing: dismissing, from: .fullPlayer)
        } onCancelled: {
            withOptionalAnimation(reduceMotion ? nil : AppMotion.gentle) {
                overshoot = 0
            }
            presentation.cancelDrag(from: .fullPlayer)
        }
    }
}
