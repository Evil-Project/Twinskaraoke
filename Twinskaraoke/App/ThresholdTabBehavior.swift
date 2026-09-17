import SwiftUI
import UIKit

/// How a threshold reveal is handed to the tab bar.
///
/// The reveal itself has no public API: `UITabBarController.MinimizeBehavior`
/// has four cases and no threshold, so a short upward scroll can only be turned
/// into a reveal by flipping the policy to `.never` — which force-expands an
/// already-minimized bar — and restoring `.onScrollDown` afterwards.
///
/// *Who performs that flip* is the open question on iOS 27: minimization is
/// animated, the reveal is not. These cases exist so the alternatives can be
/// compared on a device without a rebuild between them. `.declared` is the
/// shipping behaviour and the default; nothing changes unless it is changed in
/// the developer menu.
enum TabRevealStrategy: Int, CaseIterable, Identifiable, Sendable {
    /// Today's behaviour. SwiftUI declares `.never` for the length of a reveal.
    case declared = 0
    /// The declaration stays constant at `.onScrollDown` and only UIKit is told
    /// about the reveal, by assigning the controller's property directly. This
    /// is what `TabBarMinimizeCoordinator` did before it was removed; it was
    /// measured on an iOS 26.5 device as one clean accessory move in ~54ms,
    /// against the two-stage move the declared flip produced there.
    case uikitFlip = 1
    /// `uikitFlip`, with the assignment committed inside an explicit UIKit
    /// animation (and `performBatchUpdates` where it exists) rather than
    /// whatever ambient transaction happens to be open. This is the variant for
    /// "iOS 27 expands correctly but without animating".
    case uikitAnimatedFlip = 2
    /// `declared`, but the policy is not handed back when scrolling settles —
    /// only when the next gesture starts. This is the variant for "the reveal
    /// starts and is then cut short".
    case declaredLateHandBack = 3
    /// `uikitFlip`, and then the expansion is animated by the app, from where
    /// the accessory actually is on screen to where UIKit just put it. This is
    /// the one aimed at what the device logs actually showed: iOS 27 attaches
    /// no animation to the expansion, so the stale minimize animation holds the
    /// frame for the rest of its second and the bar arrives in two jumps. See
    /// `TabRevealTransition`.
    case adoptedTransition = 4
    /// No threshold reveal at all: `.onScrollDown` is declared and never
    /// changed, so the only reveal is UIKit's own, driven by the scroll
    /// interaction. That is the one expansion iOS 27 was measured animating
    /// properly — a ~200ms ramp across x, y and width together — because it is
    /// the interaction moving the bar rather than a policy change asking it to
    /// jump. The cost is Apple's reveal distance instead of our 72 points.
    case nativeOnly = 5
    /// The shipping default: whichever of the above is right for the OS.
    ///
    /// iOS 26 performs the policy flip's expansion properly, so it keeps the
    /// 72-point reveal unaided.
    ///
    /// iOS 27 does not animate a policy-flip expansion at all — proven against a
    /// bare tab bar with a bare accessory and none of this app around it, which
    /// glitches identically. There is no API to ask it to: `tabBarMinimizeBehavior`
    /// is unchanged since iOS 26 and carries no threshold, no state and no
    /// restoration behaviour, and iOS 27's new `UIBarMinimization` family
    /// (`minimizationBehavior`/`restorationBehavior`/`safeAreaAdjustment`) hangs off
    /// `UINavigationItem`, so it reaches navigation bars only. `nativeOnly` was the
    /// safe answer and gave up the short reveal with it, because UIKit's own reveal
    /// on iOS 27 fires only at the top of the scroll view.
    ///
    /// `adoptedTransition` was tried and withdrawn: on an iOS 27 device it
    /// oscillates between expanded and inline several times a second, and the
    /// accessory tears — the container collapses toward inline width while the
    /// tab bar stays expanded and the forward button is left outside it. It
    /// animates every descendant layer independently against a layout UIKit is
    /// still re-running underneath, so the children chase stale targets. The
    /// iOS 27 CI simulator showed none of this, which is the same simulator/
    /// device split the rest of this investigation ran into.
    ///
    /// So iOS 27 is back on `nativeOnly` while the documented native restore is
    /// tested directly — see `testNativeRevealOnScrollUp`.
    case automatic = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .declared: "SwiftUI declares .never (shipping)"
        case .uikitFlip: "UIKit flip, declaration constant"
        case .uikitAnimatedFlip: "UIKit flip, explicit animation"
        case .declaredLateHandBack: "SwiftUI declares .never, late hand-back"
        case .adoptedTransition: "UIKit flip, app animates the expansion"
        case .nativeOnly: "Native reveal only (no threshold)"
        case .automatic: "Automatic (per OS)"
        }
    }

    /// Hand-back on scroll-idle. `declaredLateHandBack` rearms at the start of
    /// the next gesture instead, which `begin(owner:offset:)` already does.
    var handsBackOnIdle: Bool { self != .declaredLateHandBack }

    /// Whether the reveal is published to SwiftUI at all. The UIKit paths keep
    /// `isRevealed` untouched on purpose: a published change is a SwiftUI update
    /// pass, and an update pass can re-apply the declared `.onScrollDown` inside
    /// the window where `.never` is supposed to be in force, losing the reveal.
    var isDeclared: Bool { self == .declared || self == .declaredLateHandBack || self == .nativeOnly }

    /// Whether the short upward scroll is watched at all. `nativeOnly` leaves
    /// the scroll views unobserved, so nothing can ask for a reveal.
    var usesThreshold: Bool { self != .nativeOnly }

    static let storageKey = "nk.tabRevealStrategy"

    /// Clears a selection left behind by the iOS 27 investigation, once.
    ///
    /// `automatic` is only the default for an *absent* key — `@AppStorage`'s
    /// default never applies over a stored value. Anyone who touched the picker
    /// while this was being chased has a concrete strategy stored, and it
    /// silently outranks the per-OS default on every later launch, which is
    /// exactly what happened: the shipping fix landed and nothing changed,
    /// because a diagnostic pick from an hour earlier was still in force.
    static func migrateStoredSelectionIfNeeded() {
        let marker = storageKey + ".automaticDefault"
        guard !UserDefaults.standard.bool(forKey: marker) else { return }
        UserDefaults.standard.set(true, forKey: marker)
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// What the developer menu has selected, unresolved. An absent key is the
    /// default rather than `declared`, which is what `rawValue: 0` would be.
    static var current: TabRevealStrategy {
        guard let raw = UserDefaults.standard.object(forKey: storageKey) as? Int else { return .automatic }
        return TabRevealStrategy(rawValue: raw) ?? .automatic
    }

    /// The strategy actually installed. Only `automatic` resolves to anything
    /// else, and only by OS version.
    var resolved: TabRevealStrategy {
        guard self == .automatic else { return self }
        if #available(iOS 27.0, *) { return .nativeOnly }
        return .declared
    }
}

/// Installs the selected strategy. SwiftUI always declares a minimize
/// behaviour — dropping the modifier on one platform is what stopped
/// downward-scroll minimization in 78cae06, because the declared default then
/// replaces `.onScrollDown` on the next update pass.
struct ThresholdTabBehavior: ViewModifier {
    let state: TabScrollRevealState?
    let strategy: TabRevealStrategy

    func body(content: Content) -> some View {
        content
            .tabBarMinimizeBehavior(declaredBehavior)
            .environment(\.tabScrollReveal, strategy.usesThreshold ? state : nil)
            .background {
                if !strategy.isDeclared, let state {
                    TabRevealBridge(
                        state: state,
                        animated: strategy == .uikitAnimatedFlip,
                        adoptsTransition: strategy == .adoptedTransition
                    )
                        .frame(width: 0, height: 0)
                }
            }
            .onChange(of: strategy.handsBackOnIdle, initial: true) { _, handsBack in
                state?.handsBackOnIdle = handsBack
            }
            .onChange(of: state?.isRevealed ?? false) { _, revealed in
                TabRevealProbe.shared.record(revealed ? "declared-reveal" : "declared-handback")
            }
    }

    private var declaredBehavior: TabBarMinimizeBehavior {
        guard strategy.isDeclared, strategy.usesThreshold, state?.isRevealed == true else {
            return .onScrollDown
        }
        return .never
    }
}

// MARK: - UIKit driver

private struct TabRevealBridge: UIViewRepresentable {
    let state: TabScrollRevealState
    let animated: Bool
    let adoptsTransition: Bool

    func makeUIView(context: Context) -> TabRevealBridgeView { TabRevealBridgeView() }

    func updateUIView(_ view: TabRevealBridgeView, context: Context) {
        view.animated = animated
        view.adoptsTransition = adoptsTransition
        view.install(state: state)
    }

    static func dismantleUIView(_ view: TabRevealBridgeView, coordinator: ()) {
        view.remove()
    }
}

final class TabRevealBridgeView: UIView {
    var animated = false
    var adoptsTransition = false
    private let driverID = UUID()
    private weak var state: TabScrollRevealState?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { remove() } else if let state { install(state: state) }
    }

    func install(state: TabScrollRevealState) {
        self.state = state
        state.installDriver(owner: driverID) { [weak self] revealed, reduceMotion, completion in
            guard let self else {
                completion()
                return
            }
            apply(revealed: revealed, reduceMotion: reduceMotion, completion: completion)
        }
    }

    func remove() {
        state?.removeDriver(owner: driverID)
    }

    private func apply(revealed: Bool, reduceMotion: Bool, completion: @escaping () -> Void) {
        guard let controller = Self.tabBarController(in: window?.rootViewController) else {
            completion()
            return
        }
        let behavior: UITabBarController.MinimizeBehavior = revealed ? .never : .onScrollDown
        guard controller.tabBarMinimizeBehavior != behavior else {
            completion()
            return
        }
        TabRevealProbe.shared.record(revealed ? "uikit-reveal" : "uikit-handback", controller: controller)

        // The hand-back must not look like a second transition, and neither
        // must a reveal under Reduce Motion.
        guard revealed, !reduceMotion else {
            UIView.performWithoutAnimation {
                Self.commit(behavior, on: controller, batched: false)
            }
            completion()
            return
        }

        if adoptsTransition {
            TabRevealTransition.animatingExpansion(in: controller) {
                Self.commit(behavior, on: controller, batched: false)
            }
            // Not a `CATransaction` completion block. The policy stays `.never`
            // until this runs and the state machine stays mid-reveal, so a
            // completion that never fires is a tab bar that can never minimize
            // again — which is exactly what a transaction with no registered
            // animation, or one nested in an outer commit, can produce. A plain
            // timer cannot be starved.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(TabRevealTransition.duration * 1000)))
                completion()
            }
            return
        }

        guard animated else {
            UIView.performWithoutAnimation {
                Self.commit(behavior, on: controller, batched: false)
            }
            completion()
            return
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            Self.commit(behavior, on: controller, batched: true)
            controller.view.layoutIfNeeded()
        }
        CATransaction.commit()
    }

    /// `performBatchUpdates` is iOS 27 and public, so a binary built against an
    /// older SDK reaches it by selector. Outside a batch the assignment still
    /// stands on its own.
    private static func commit(
        _ behavior: UITabBarController.MinimizeBehavior,
        on controller: UITabBarController,
        batched: Bool
    ) {
        let assign = { controller.tabBarMinimizeBehavior = behavior }
        guard batched else {
            assign()
            return
        }
        let selector = NSSelectorFromString("performBatchUpdates:")
        if controller.responds(to: selector) {
            let block: @convention(block) () -> Void = assign
            controller.perform(selector, with: block)
        } else {
            assign()
        }
    }

    static func tabBarController(in root: UIViewController?) -> UITabBarController? {
        guard let root else { return nil }
        if let tab = root as? UITabBarController { return tab }
        for child in root.children {
            if let tab = tabBarController(in: child) { return tab }
        }
        return tabBarController(in: root.presentedViewController)
    }
}
