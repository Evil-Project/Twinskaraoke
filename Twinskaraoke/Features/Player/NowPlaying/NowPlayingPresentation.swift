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

    /// Where the mini player's artwork sits, in global coordinates, and where
    /// the full player's sits. The morph interpolates between them off
    /// `progress`, so it tracks the finger rather than running on its own
    /// clock — which is why this is measured rather than left to
    /// `matchedGeometryEffect`, which only animates state changes.
    private(set) var barArtworkFrame: CGRect?
    private(set) var playerArtworkFrame: CGRect?

    /// Whether the flying artwork is standing in for the two real ones. Both
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
        (isTransitioning || isAnimatingTransition)
            && barArtworkFrame != nil
            && playerArtworkFrame != nil
    }

    /// True from the start of an animated open or close until the spring has
    /// settled. Nothing observes the animation's completion, so it is timed.
    private(set) var isAnimatingTransition = false
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// A little longer than `AppMotion.gentle` takes to come to rest. Ending
    /// early would swap the flying artwork for the real one mid-flight, which
    /// is the one visible seam this is meant to remove; ending late costs
    /// nothing, because by then the two are in the same place.
    private static let settleDuration = Duration.milliseconds(700)

    func reportBarArtworkFrame(_ frame: CGRect?) {
        barArtworkFrame = frame.flatMap { $0.width > 0 ? $0 : nil }
    }

    func reportPlayerArtworkFrame(_ frame: CGRect?) {
        playerArtworkFrame = frame.flatMap { $0.width > 0 ? $0 : nil }
    }

    /// Mirrors `\.appReduceMotion` so the intent methods below can animate
    /// consistently no matter which view calls them — `FullScreenPlayerView`'s
    /// grabber calls `collapse()` from deep inside the player, and requiring
    /// every such call site to remember its own `withAnimation` is how the two
    /// directions drift apart. `NowPlayingOverlay` keeps this current.
    @ObservationIgnored var prefersReducedMotion = false

    private init() {}

    // MARK: - Intent

    func expand() {
        guard !isExpanded else { return }
        AppHaptic.commit.play()
        isExpanded = true
        animate(to: 1)
    }

    func collapse() {
        guard isExpanded else { return }
        AppHaptic.dismiss.play()
        isExpanded = false
        animate(to: 0)
    }

    // MARK: - Interactive drag

    /// Tracks the finger. Deliberately unanimated: an animation here would
    /// lag the drag by its own duration, which is the "indirect" feel we
    /// already rejected once while trying to tune the old library.
    func drag(to progress: Double) {
        // Guarded rather than assigned unconditionally: this runs on every
        // frame of the drag, and an observable write per frame invalidates
        // every view reading the presentation for no change at all.
        if isAnimatingTransition {
            settleTask?.cancel()
            settleTask = nil
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
    func endDrag(dismissing: Bool) {
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
        settleTask?.cancel()
        settleTask = nil
        isAnimatingTransition = false
        isExpanded = false
        progress = 0
    }

    // MARK: - Driving the animation

    private func animate(to target: Double) {
        settleTask?.cancel()
        settleTask = nil
        guard let animation = transitionAnimation else {
            // Reduce Motion: the change is instant, so there is no flight for
            // the artwork to be in and nothing to hold the gate open for.
            isAnimatingTransition = false
            progress = target
            return
        }
        isAnimatingTransition = true
        withAnimation(animation) {
            progress = target
        }
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleDuration)
            guard !Task.isCancelled else { return }
            self?.isAnimatingTransition = false
            self?.settleTask = nil
        }
    }

    /// Large surfaces move on `gentle`; this is the largest one in the app.
    private var transitionAnimation: Animation? {
        prefersReducedMotion ? nil : AppMotion.gentle
    }
}
