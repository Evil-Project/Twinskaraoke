import SwiftUI
import UIKit

/// Keeps a pushed zoom destination off iOS 26's interactive-dismissal path.
///
/// `.navigationTransition(.zoom)` on a push has an iOS 26 defect: after an
/// *interactive* dismissal the transition keeps running, and UIKit will not
/// begin another navigation until it finishes — so the next tap does nothing for
/// as long as the animation lasts, which scales with how far the finger dragged.
/// Worse, the outgoing screen keeps hit testing for that whole time, so a tap
/// meant for the grid underneath lands on the shrinking detail view instead.
/// Dismissing the same screen with the back button completes immediately.
/// Reported and unanswered since June 2025:
/// https://developer.apple.com/forums/thread/789010
///
/// So the interactive path is removed and replaced with an equivalent gesture
/// that goes through `dismiss()` — the back-button path. The zoom still
/// animates; it simply is not finger-driven.
///
/// Note what this buys beyond responsiveness: a push is dismissed by a
/// *horizontal* gesture, so vertical pulls stay free for the destination — which
/// is why PlaylistDetailView can keep its pull-to-reveal search without any
/// staging or arbitration. A modal presentation adds a vertical drag-dismiss
/// instead, which fights that reveal, and also covers the LNPopup mini player.
/// Pushing avoids both. (Horizontal, not edge-limited: see below.)
///
/// **The replacement has to cover the whole screen, not just the edge.** UIKit's
/// content swipe is not edge-limited: measured on iOS 26.5, a right-swipe
/// starting 80pt in dismissed the destination. An earlier version of this put a
/// 20pt gesture strip along the leading edge instead, and suppressing the system
/// recogniser then had a second effect nobody wanted — with nothing claiming a
/// horizontal drag over the content, the row underneath received it as a plain
/// tap and started playing, because a touch that ends inside a button's own
/// bounds is a tap no matter how far it travelled sideways. So the replacement
/// is a real pan on the whole screen: it cancels content touches the moment it
/// begins, and dismisses on release.
///
/// Delete this once Apple fixes the transition, and restore the real
/// interactive dismissal — finger-tracking is the better interaction.
struct ZoomPushDismissal: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var suppressor = InteractiveDismissalSuppressor()
    /// Set the instant a dismissal is committed, not on `onDisappear`: that
    /// fires when the transition *finishes* (measured ~0.9s later), and for the
    /// whole shrink in between this screen is still on top of the hit-testing
    /// order. A tap aimed at the tile underneath landed on a song row here and
    /// started playing it.
    @State private var isDismissing = false
    /// True until the push transition finishes. Screens that start playback on a
    /// single tap read this and hold those taps back: the zoom does not gate
    /// input, and it runs ~0.9s — measured — so a second tap aimed at the grid
    /// tile arrives while this screen is still flying in, over whatever sits at
    /// that Y coordinate.
    @State private var isArriving = true

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isDismissing)
            .environment(\.zoomPushIsArriving, isArriving)
            .background(
                ZoomDismissalBridge(
                    suppressor: suppressor,
                    onSwipeBack: {
                        isDismissing = true
                        AppHaptic.selection.play()
                        dismiss()
                    },
                    onArrived: { isArriving = false }
                )
            )
            // Both call the same evaluation: it asks whether this screen is the
            // one on top, rather than trusting appear/disappear to be paired.
            .onAppear {
                isDismissing = false
                suppressor.update()
            }
            .onDisappear { suppressor.update() }
    }
}

extension View {
    func zoomPushDismissal(isEnabled: Bool) -> some View {
        modifier(ZoomPushDismissalGate(isEnabled: isEnabled))
    }
}

private struct ZoomPushDismissalGate: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(ZoomPushDismissal())
        } else {
            content
        }
    }
}

/// One per zoom destination on screen. Decides *whether* its screen wants the
/// interactive dismissal suppressed; the actual disabling is shared per
/// navigation controller, because the recognisers are too.
@MainActor
final class InteractiveDismissalSuppressor {
    /// Single switch for the private-API dependency below.
    ///
    /// Everything here hangs off matching UIKit's dismissal recognisers by type
    /// name. Turning this off restores stock behaviour — the interactive
    /// dismissal comes back, and with it the iOS 26 delay — without touching any
    /// call site. Flip it if a future iOS renames the classes, or if the
    /// dependency is ever considered a submission risk.
    static let isEnabled = true

    weak var navigationController: UINavigationController?
    /// The navigation controller's own child that hosts this screen. Identity is
    /// what tells a real pop apart from SwiftUI churn.
    weak var hostController: UIViewController?
    private var isHolding = false

    /// Suppression follows *who is on top*, not SwiftUI's appear/disappear
    /// pairing. Those fire repeatedly for a single visit — this project's device
    /// logs show appeared and disappeared 1ms apart, over and over — so
    /// restoring on every disappear left the screen unprotected for the rest of
    /// the visit, which is one way the interactive path came back. Asking the
    /// navigation stack instead is idempotent: churn re-evaluates to the same
    /// answer, a genuine pop evaluates to false, and a screen pushed on top
    /// hands suppression over to that screen (or gives it up entirely, so a
    /// plain push on top keeps its ordinary interactive pop).
    func update() {
        guard Self.isEnabled else { return }
        let wants = isTopOfStack
        guard wants != isHolding else { return }
        isHolding = wants
        suppression?.setHolder(ObjectIdentifier(self), wants: wants)
    }

    private var isTopOfStack: Bool {
        guard let navigationController else { return false }
        // No host means the responder walk came up empty; assume this screen is
        // the one on top rather than leaving it unprotected. `deinit` releases.
        guard let hostController else { return true }
        return navigationController.topViewController === hostController
    }

    private var suppression: NavigationDismissalSuppression? {
        navigationController.map { NavigationDismissalSuppression.attached(to: $0) }
    }

    isolated deinit {
        guard isHolding else { return }
        suppression?.setHolder(ObjectIdentifier(self), wants: false)
    }
}

/// Disables the recognisers that drive an interactive dismissal, for as long as
/// at least one zoom destination on this navigation controller wants that.
///
/// Reference counted because the recognisers are shared: with a zoom destination
/// pushed from another zoom destination — the art gallery does exactly this,
/// artist then artwork — the parent's teardown would otherwise re-enable them
/// underneath the child.
@MainActor
final class NavigationDismissalSuppression {
    /// Measured on iOS 26.5, from a pushed `.navigationTransition(.zoom)`
    /// destination — four recognisers, not the two this used to disable:
    ///
    /// - `_UIParallaxTransitionPanGestureRecognizer` ×2 on the navigation
    ///   controller's view. Only the first is reachable through
    ///   `interactivePopGestureRecognizer`.
    /// - `_UIParallaxTransitionPanGestureRecognizer` and
    ///   `_UIContentSwipeDismissGestureRecognizer` on the destination's own
    ///   hosting view. **These are the ones that were missed**, and the content
    ///   swipe is what actually drives the zoom dismissal: it was seen going
    ///   began → changed while both recognisers on the navigation view sat
    ///   disabled, popping the screen on the broken interactive path.
    ///
    /// Matching on type names is unpleasant but narrow, and fails safe — no
    /// match, nothing disabled.
    private static let driverNames = ["ParallaxTransition", "ContentSwipeDismiss"]

    private static let table = NSMapTable<UINavigationController, NavigationDismissalSuppression>
        .weakToStrongObjects()

    static func attached(to navigationController: UINavigationController) -> NavigationDismissalSuppression {
        if let existing = table.object(forKey: navigationController) { return existing }
        let created = NavigationDismissalSuppression(navigationController: navigationController)
        table.setObject(created, forKey: navigationController)
        return created
    }

    private weak var navigationController: UINavigationController?
    private var holders: Set<ObjectIdentifier> = []
    private var disabled: [UIGestureRecognizer] = []
    private var rescanTask: Task<Void, Never>?

    private init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func setHolder(_ holder: ObjectIdentifier, wants: Bool) {
        let changed = wants ? holders.insert(holder).inserted : holders.remove(holder) != nil
        guard changed else { return }
        apply()
    }

    private func apply() {
        guard !holders.isEmpty else {
            rescanTask?.cancel()
            rescanTask = nil
            for recogniser in disabled {
                recogniser.isEnabled = true
            }
            disabled = []
            return
        }
        scan()
        // The destination's own recognisers are installed by the transition, and
        // there is no callback for that, so one scan on appear can be too early.
        // A short burst covers the transition window and then stops; a dismissal
        // recogniser cannot appear later than the transition that owns it.
        rescanTask?.cancel()
        rescanTask = Task { @MainActor [weak self] in
            for step in [50, 200, 500] {
                try? await Task.sleep(for: .milliseconds(step))
                guard !Task.isCancelled, let self, !self.holders.isEmpty else { return }
                self.scan()
            }
        }
    }

    /// Walks the whole navigation view tree, not just its root view: two of the
    /// four recognisers live on the destination's hosting view.
    private func scan() {
        guard let root = navigationController?.view else { return }
        var found: [UIGestureRecognizer] = []
        collect(from: root, into: &found)
        guard !found.isEmpty else { return }
        for recogniser in found {
            recogniser.isEnabled = false
        }
        disabled.append(contentsOf: found)
    }

    private func collect(from view: UIView, into found: inout [UIGestureRecognizer]) {
        for recogniser in view.gestureRecognizers ?? []
        where recogniser.isEnabled && Self.isDismissalDriver(recogniser) {
            found.append(recogniser)
        }
        for subview in view.subviews {
            collect(from: subview, into: &found)
        }
    }

    private static func isDismissalDriver(_ recogniser: UIGestureRecognizer) -> Bool {
        let name = String(describing: type(of: recogniser))
        return driverNames.contains { name.contains($0) }
    }
}

/// Finds the enclosing navigation controller and this screen's own view
/// controller, hands both to the suppressor, and installs the swipe-back pan on
/// the screen. The decision to suppress is the suppressor's.
private struct ZoomDismissalBridge: UIViewRepresentable {
    let suppressor: InteractiveDismissalSuppressor
    let onSwipeBack: () -> Void
    let onArrived: () -> Void

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.suppressor = suppressor
        view.swipeBack = context.coordinator
        view.onArrived = onArrived
        context.coordinator.onSwipeBack = onSwipeBack
        return view
    }

    func updateUIView(_ view: BridgeView, context: Context) {
        view.suppressor = suppressor
        view.onArrived = onArrived
        context.coordinator.onSwipeBack = onSwipeBack
    }

    func makeCoordinator() -> SwipeBackDriver { SwipeBackDriver() }

    static func dismantleUIView(_ view: BridgeView, coordinator: SwipeBackDriver) {
        coordinator.uninstall()
    }

    final class BridgeView: UIView {
        var suppressor: InteractiveDismissalSuppressor?
        var swipeBack: SwipeBackDriver?
        var onArrived: (() -> Void)?

        /// The push's own transition, asked directly rather than guessed at with
        /// a delay: `transitionCoordinator` is non-nil for exactly as long as the
        /// zoom runs, and nil already when a screen appears without one (reduce
        /// motion, or a re-appear after a sub-screen pops).
        private func reportArrival(host: UIViewController) {
            guard let coordinator = host.transitionCoordinator else {
                onArrived?()
                return
            }
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.onArrived?()
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let suppressor else { return }
            var responder: UIResponder? = self
            var innermostController: UIViewController?
            var hops = 0
            while let current = responder, hops < 60 {
                if let nav = current as? UINavigationController {
                    suppressor.navigationController = nav
                    // The screen's own controller is the one whose parent is the
                    // navigation controller — SwiftUI nests hosting controllers,
                    // so the innermost one is usually not it.
                    let host = innermostController.flatMap { controller in
                        sequence(first: controller, next: \.parent).first { $0.parent === nav }
                    }
                    suppressor.hostController = host
                    // onAppear may have run before the controller was known.
                    suppressor.update()
                    guard let host else {
                        onArrived?()
                        return
                    }
                    // Installed only where the system gesture is suppressed: the
                    // replacement stands in for it, so the escape hatch has to
                    // turn off both or neither. On the screen's own view, so it
                    // dies with the screen instead of outliving it on the
                    // navigation view.
                    if InteractiveDismissalSuppressor.isEnabled {
                        swipeBack?.install(on: host.view)
                    }
                    reportArrival(host: host)
                    return
                }
                if innermostController == nil, let controller = current as? UIViewController {
                    innermostController = controller
                }
                responder = current.next
                hops += 1
            }
        }
    }
}

/// The replacement for UIKit's suppressed content swipe: same reach, but it
/// dismisses through `dismiss()` instead of driving the transition interactively.
@MainActor
final class SwipeBackDriver: NSObject, UIGestureRecognizerDelegate {
    /// How far the finger must travel before a release counts as "back", and the
    /// flick that gets there sooner.
    private static let triggerDistance: CGFloat = 60
    private static let flickDistance: CGFloat = 24
    private static let flickVelocity: CGFloat = 800

    var onSwipeBack: () -> Void = {}
    private weak var installedView: UIView?
    private var recogniser: UIPanGestureRecognizer?

    func install(on view: UIView) {
        guard installedView !== view else { return }
        uninstall()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        // Left at its default: cancelling content touches when the pan begins is
        // what stops a sideways drag across a song row from playing it.
        view.addGestureRecognizer(pan)
        recogniser = pan
        installedView = view
    }

    func uninstall() {
        if let recogniser, let installedView {
            installedView.removeGestureRecognizer(recogniser)
        }
        recogniser = nil
        installedView = nil
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended, let view = pan.view else { return }
        let sign = Self.backwardSign(in: view)
        let translation = pan.translation(in: view).x * sign
        let velocity = pan.velocity(in: view).x * sign
        guard abs(pan.translation(in: view).y) < translation else { return }
        let isDecided = translation > Self.triggerDistance
            || (translation > Self.flickDistance && velocity > Self.flickVelocity)
        guard isDecided else { return }
        onSwipeBack()
    }

    /// "Back" is leftward in a right-to-left layout, as it is for the system
    /// gesture this replaces. No RTL localisation ships today; this is one line
    /// rather than a surprise when one does.
    private static func backwardSign(in view: UIView) -> CGFloat {
        view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
    }

    /// Rightward and horizontal, judged on the opening movement. Anything else —
    /// including the vertical pull that reveals PlaylistDetailView's search
    /// field — is none of this gesture's business.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view
        else { return false }
        let velocity = pan.velocity(in: view)
        let backward = velocity.x * Self.backwardSign(in: view)
        return backward > 0 && backward > abs(velocity.y) * 1.5
    }

    /// Scrolling must keep working while this is armed — but nothing else may
    /// run alongside. Blanket simultaneity let the row underneath a sideways
    /// drag recognise its own tap and start playing: a pan cancels *touches* in
    /// its view, which does nothing to a competing gesture recogniser, so the
    /// only thing that stops the tap is refusing to share the touch with it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        other.view is UIScrollView
    }

    /// Yield to anything that can genuinely scroll horizontally — a carousel in
    /// a destination owns its own sideways drags. None of today's zoom
    /// destinations has one; this is so adding one does not break it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf other: UIGestureRecognizer
    ) -> Bool {
        guard let scrollView = other.view as? UIScrollView,
              other === scrollView.panGestureRecognizer
        else { return false }
        return scrollView.contentSize.width > scrollView.bounds.width + 1
    }
}
