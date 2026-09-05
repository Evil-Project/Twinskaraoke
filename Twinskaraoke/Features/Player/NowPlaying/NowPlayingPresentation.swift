import Observation
import SwiftUI

/// Whether the full-screen player is showing, and how far.
///
/// One scalar drives the whole presentation. That much is borrowed from the
/// dependency this replaces — LNPopupController derives every frame it touches
/// from a single percentage, so its interactive and animated paths cannot
/// disagree, and that is the right shape. What is not borrowed is where the
/// scalar comes from: there, it was read back out of a `UIView`'s live frame,
/// which is why the state machine needed six variables to describe three
/// states. Here it is just a stored property, and the views follow it.
///
/// `isExpanded` is the *committed* state, not the visual one. A dismissal drag
/// in progress leaves it true until the gesture actually commits, so things
/// that key off "the player is open" — the ambient background's breathing
/// (`FullScreenPlayerView`), Shimeji's floor (`ShimejiEngine`) — do not flicker
/// while someone drags halfway down and changes their mind.
@MainActor
@Observable
final class NowPlayingPresentation {
    static let shared = NowPlayingPresentation()

    /// 0 with the player fully off-screen, 1 with it fully open. Written
    /// continuously while a drag is in flight and animated to an endpoint when
    /// one commits.
    private(set) var progress: Double = 0
    enum DragSource { case miniPlayer, fullPlayer }
    private(set) var dragSource: DragSource?
    /// Retained through settlement/cancellation. Interactive closing keeps the
    /// real cover attached; only a committed close can start the landing morph.
    private var artworkTransitionSource: DragSource?
    private(set) var isSettlingArtwork = false
    var isDragging: Bool { dragSource != nil }

    /// The mini player can receive a fresh contact as soon as closing commits.
    /// Spring completion may arrive after it is already visible; rejecting a
    /// touch during that tail loses the entire gesture, even after completion.
    var canBeginMiniPlayerContact: Bool { !isExpanded && !isDragging }

    func cancelDrag(from source: DragSource) {
        guard dragSource == source else { return }
        dragSource = nil
        animate(to: isExpanded ? 1 : 0)
    }

    func animationDidComplete(token: Int) {
        PlayerGestureTrace.record("animation completion token=\(token) current=\(animationToken) progress=\(progress)")
        guard token == animationToken else { return }
        isAnimatingTransition = false
        artworkTransitionSource = nil
        isSettlingArtwork = false
    }

    /// Whether the player is open as a matter of intent. See the type's
    /// documentation for why this is not `progress > 0.5`.
    private(set) var isExpanded = false

    /// Whether the overlay needs to render and take touches at all. False in
    /// the resting collapsed state, which is what keeps the player out of the
    /// hit-testing path while someone is using the rest of the app.
    var isPresenting: Bool {
        isExpanded || progress > 0
    }

    /// True only mid-flight, in either direction. The artwork morph rides this.
    var isTransitioning: Bool {
        progress > 0 && progress < 1
    }

    /// The mini artwork in window coordinates and the full artwork in the
    /// stationary full-player coordinate space. The morph interpolates off
    /// `progress`, so it tracks the finger rather than running on its own
    /// clock — which is why this is measured rather than left to
    /// `matchedGeometryEffect`, which only animates state changes.
    private(set) var barArtworkFrame: CGRect?
    private(set) var barFrame: CGRect?
    private(set) var playerArtworkFrame: CGRect?

    /// Whether a transition image stands in for the full artwork. Both
    /// frames have to be known: before the first layout pass of either, there
    /// is nothing to interpolate, and a morph from `.zero` reads as the artwork
    /// flying in from the top-left corner.
    ///
    /// `isAnimatingTransition` is in here as well as `isTransitioning`, and it
    /// has to be. `withAnimation` sets `progress` to its destination
    /// *immediately* and animates only the rendering, so on a tap-to-open the
    /// stored value is 1 before the player has moved and `isTransitioning` is
    /// false for the entire animation. Gating on that alone would give a morph
    /// that appears under a dragging finger and never for a tap.
    ///
    /// The flying artwork's geometry needs no such help: it is computed from
    /// `progress`, so a drag updates it per frame, and an animated change moves
    /// its `frame` and `position` between two values inside the transaction,
    /// which SwiftUI interpolates for us. Only the question of *whether it is
    /// on screen* has to be held open for the duration.
    var isMorphingArtwork: Bool {
        (artworkTransitionSource == .miniPlayer || isSettlingArtwork)
            && (isTransitioning || isAnimatingTransition)
            && barArtworkFrame != nil
            && playerArtworkFrame != nil
    }

    /// Cleared by the rendering transaction's completion, including Reduce Motion.
    private(set) var isAnimatingTransition = false

    var isClosingTransition: Bool {
        isAnimatingTransition && artworkTransitionSource == .fullPlayer && animationTarget == 0
    }

    func prepareClosingSettlement() {
        guard isClosingTransition, barFrame != nil, barArtworkFrame != nil, playerArtworkFrame != nil else { return }
        isSettlingArtwork = true
    }

    func reportBarFrame(_ frame: CGRect?) {
        barFrame = frame.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
    }

    func reportBarArtworkFrame(_ frame: CGRect?) {
        barArtworkFrame = frame.flatMap { $0.width > 0 ? $0 : nil }
    }

    func reportPlayerArtworkFrame(_ frame: CGRect?) {
        playerArtworkFrame = frame.flatMap { $0.width > 0 ? $0 : nil }
    }

    init() {}

    // MARK: - Intent

    func expand() {
        guard !isExpanded, !isDragging else { return }
        artworkTransitionSource = .miniPlayer
        isSettlingArtwork = false
        AppPerformance.event("Player Expand")
        AppHaptic.commit.play()
        isExpanded = true
        animate(to: 1)
    }

    func collapse() {
        guard isExpanded, !isDragging else { return }
        artworkTransitionSource = .fullPlayer
        isSettlingArtwork = false
        AppPerformance.event("Player Collapse")
        AppHaptic.dismiss.play()
        isExpanded = false
        animate(to: 0)
    }

    // MARK: - Interactive drag

    /// Tracks the finger. Deliberately unanimated: an animation here would
    /// lag the drag by its own duration, which is the "indirect" feel we
    /// already rejected once while trying to tune the old library.
    func drag(to progress: Double, from source: DragSource) {
        // Both surfaces stay mounted. A recognizer from the inactive surface
        // must never overwrite (or finish) the other surface's contact.
        guard isExpanded == (source == .fullPlayer),
              dragSource == nil || dragSource == source else { return }
        if dragSource == nil {
            dragSource = source
            artworkTransitionSource = source
            isSettlingArtwork = false
        }
        // Guarded rather than assigned unconditionally: this runs on every
        // frame of the drag, and an observable write per frame invalidates
        // every view reading the presentation for no change at all.
        if isAnimatingTransition {
            animationToken &+= 1
            isAnimatingTransition = false
        }
        self.progress = min(1, max(0, progress))
    }

    /// Settles a released drag onto whichever endpoint it committed to.
    ///
    /// The haptic fires only on a real change of state, so springing back from
    /// an abandoned drag stays silent — it is not an outcome, and marking it
    /// as one makes the player feel like it did something the user did not ask
    /// for.
    func endDrag(dismissing: Bool, from source: DragSource) {
        guard dragSource == source else { return }
        dragSource = nil
        let wasExpanded = isExpanded
        isExpanded = !dismissing
        if wasExpanded != isExpanded {
            (isExpanded ? AppHaptic.commit : AppHaptic.dismiss).play()
        }
        animate(to: dismissing ? 0 : 1)
    }

    /// Drops the player without ceremony. For the case where the thing being
    /// presented stops existing — the queue empties, the song is cleared —
    /// where an animated close would be animating a player that has nothing
    /// left to show.
    func dismissImmediately() {
        AppPerformance.event("Player Immediate Dismiss")
        isAnimatingTransition = false
        dragSource = nil
        artworkTransitionSource = nil
        isSettlingArtwork = false
        isExpanded = false
        progress = 0
    }

    // MARK: - Driving the animation

    /// Where an animated transition is heading, and a token that changes every
    /// time one is requested.
    ///
    /// `NowPlayingOverlay` watches the token and performs the move itself,
    /// inside its own `withAnimation`. Two earlier arrangements were wrong in
    /// different ways, and both are worth remembering.
    ///
    /// Calling `withAnimation` *here* only animated one direction: a
    /// transaction does not cross a hosting boundary, and `collapse()` and
    /// `endDrag()` are called from inside the overlay while `expand()` comes
    /// from `MiniPlayerBar`, which lives in the tab bar's accessory slot.
    ///
    /// Replacing that with `.animation(_:value:)` on the overlay fixed the
    /// direction but animated the player's whole subtree. During a drag that
    /// modifier fires every frame with a nil animation, which interrupts any
    /// animation already running inside the player — the scrub bar's fill
    /// animates its width over 0.25s on every playback tick, so it visibly
    /// juddered back and forth while the player was dragged, but only while
    /// something was playing.
    ///
    /// Driving it from the overlay's own `onChange` keeps the animation in the
    /// right tree and scopes it to one update per transition instead of one
    /// per frame.
    private(set) var animationTarget: Double = 0
    private(set) var animationToken = 0

    /// Applied by `NowPlayingOverlay` inside its own animation.
    func applyAnimationTarget() {
        PlayerGestureTrace.record("animation apply token=\(animationToken) target=\(animationTarget)")
        progress = animationTarget
    }

    private func animate(to target: Double) {
        isAnimatingTransition = true
        animationTarget = target
        animationToken &+= 1
    }
}

// MARK: - Safe-area handoff

private struct PlayerSafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue: EdgeInsets?  = nil
}

extension EnvironmentValues {
    /// The window's real safe-area insets, for a player hosted inside a view
    /// that ignores the safe area.
    ///
    /// `FullScreenPlayerView` lays itself out against the insets and needs the
    /// true ones, but its own `GeometryReader` sits inside `NowPlayingOverlay`,
    /// which has already ignored them so the player can paint edge to edge —
    /// and a reader below that point reports zero. Nil outside the overlay, so
    /// previews and any other host keep reading their own geometry.
    var playerSafeAreaInsets: EdgeInsets? {
        get { self[PlayerSafeAreaInsetsKey.self] }
        set { self[PlayerSafeAreaInsetsKey.self] = newValue }
    }
}
