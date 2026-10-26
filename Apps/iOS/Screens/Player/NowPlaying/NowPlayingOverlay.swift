import SwiftUI
struct NowPlayingOverlay: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    let safeAreaInsets: EdgeInsets

    private let presentation = NowPlayingPresentation.shared
    private let snapshot = NowPlayingSnapshotState.shared
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
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        // Keep the mini player's active opening gesture in its original host.
        // The overlay starts accepting touches after that gesture commits.
        .allowsHitTesting(presentation.isExpanded)
        // Off-screen is not hidden as far as VoiceOver is concerned: a parked
        // player is still in the accessibility tree, and would otherwise sit
        // there as a screenful of focusable controls behind the app.
        .accessibilityHidden(!presentation.isPresenting)
        .onChange(of: presentation.animationToken) { _, _ in
            withTransaction(Transaction(animation: nil)) {
                closingTransition = nil
                closingPhase = 0
            }
            guard presentation.isAnimatingTransition else { return }
            let token = presentation.animationToken
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
            let animation: Animation? = reduceMotion ? nil : closingTransition != nil
                ? .linear(duration: PlayerClosingGeometry.duration)
                : .spring(response: 0.38, dampingFraction: 0.9)
            withAnimation(animation, completionCriteria: .removed) {
                presentation.applyAnimationTarget()
                closingPhase = 1
            } completion: {
                guard token == presentation.animationToken else { return }
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
        PlayerPanGesture(canBegin: {
            presentation.isExpanded && !presentation.isDragging && !AudioPlayerManager.shared.isEditingProgress
        }) { translation in
            guard presentation.isExpanded else { return }
            withTransaction(Transaction(animation: nil)) {
                let travel = PlayerDismissMetrics.dragOffset(
                    forTranslation: translation, height: height
                )
                if travel >= 0 {
                    overshoot = 0
                    presentation.drag(to: PlayerDismissMetrics.progress(forOffset: travel, height: height), from: .fullPlayer)
                } else {
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
