import SwiftUI
import UIKit

/// Keeps a pushed zoom destination off the interactive-pop path.
///
/// `.navigationTransition(.zoom)` on a push has an iOS 26 defect: after an
/// *interactive* dismissal the transition keeps running, and UIKit will not
/// begin another navigation until it finishes — so the next tap does nothing for
/// as long as the animation lasts, which scales with how far the finger dragged.
/// Dismissing the same screen with the back button completes immediately.
/// Reported and unanswered since June 2025:
/// https://developer.apple.com/forums/thread/789010
///
/// So the interactive path is removed and replaced with an equivalent gesture
/// that goes through `dismiss()` — the back-button path. The zoom still
/// animates; it simply is not finger-driven.
///
/// Note what this buys beyond responsiveness: a push's interactive dismissal is
/// an *edge* pan (`_UIParallaxTransitionPanGestureRecognizer`), so vertical
/// pulls stay free for the destination — which is why PlaylistDetailView can
/// keep its pull-to-reveal search without any staging or arbitration. A modal
/// presentation adds a vertical drag-dismiss instead, which fights that reveal,
/// and also covers the LNPopup mini player. Pushing avoids both.
///
/// Delete this once Apple fixes the transition, and restore the real
/// interactive dismissal — finger-tracking is the better interaction.
struct ZoomPushDismissal: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var suppressor = TransitionPanSuppressor()

    /// Mirrors UIKit's screen-edge pan, so the strip cannot swallow content taps.
    private static let edgeWidth: CGFloat = 20
    private static let triggerDistance: CGFloat = 60

    func body(content: Content) -> some View {
        content
            .background(NavigationControllerLocator(suppressor: suppressor))
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: Self.edgeWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { value in
                                guard value.translation.width > Self.triggerDistance,
                                      abs(value.translation.height) < value.translation.width
                                else { return }
                                AppHaptic.selection.play()
                                dismiss()
                            }
                    )
                    .ignoresSafeArea()
            }
            // Bound to the view's own lifecycle. Driving this from
            // `didMoveToWindow` undid it microseconds later as SwiftUI churned
            // the backing view, and from `dismantleUIView` it ran a whole visit
            // late — both produced tests that never had the intended state.
            .onAppear { suppressor.suppress() }
            .onDisappear { suppressor.restore() }
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

@MainActor
final class TransitionPanSuppressor {
    /// Single switch for the private-API dependency below.
    ///
    /// Everything here hangs off matching `_UIParallaxTransitionPanGestureRecognizer`
    /// by type name. Turning this off restores stock behaviour — the interactive
    /// pop comes back, and with it the iOS 26 delay — without touching any call
    /// site. Flip it if a future iOS renames the class, or if the dependency is
    /// ever considered a submission risk.
    static let isEnabled = true

    weak var navigationController: UINavigationController?
    private var suppressed: [UIGestureRecognizer] = []

    func suppress() {
        guard Self.isEnabled, suppressed.isEmpty, let nav = navigationController else { return }
        // Both instances, not just `interactivePopGestureRecognizer`: the zoom
        // installs a second recogniser of the same private class, and only the
        // first is reachable through that property. Matching on the type name is
        // unpleasant but narrow, and fails safe — no match, nothing disabled.
        let targets = (nav.view.gestureRecognizers ?? []).filter { recogniser in
            String(describing: type(of: recogniser)).contains("ParallaxTransition")
                && recogniser.isEnabled
        }
        guard !targets.isEmpty else { return }
        for target in targets {
            target.isEnabled = false
        }
        suppressed = targets
    }

    func restore() {
        for recogniser in suppressed {
            recogniser.isEnabled = true
        }
        suppressed = []
    }
}

/// Hands the enclosing navigation controller to the suppressor; enabling and
/// disabling is driven by SwiftUI's lifecycle, not by this view.
private struct NavigationControllerLocator: UIViewRepresentable {
    let suppressor: TransitionPanSuppressor

    func makeUIView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.suppressor = suppressor
        return view
    }

    func updateUIView(_ view: LocatorView, context: Context) {
        view.suppressor = suppressor
    }

    final class LocatorView: UIView {
        var suppressor: TransitionPanSuppressor?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let suppressor else { return }
            var responder: UIResponder? = self
            var hops = 0
            while let current = responder, hops < 60 {
                if let nav = current as? UINavigationController {
                    suppressor.navigationController = nav
                    // onAppear may have run before the controller was known.
                    suppressor.suppress()
                    return
                }
                responder = current.next
                hops += 1
            }
        }
    }
}
