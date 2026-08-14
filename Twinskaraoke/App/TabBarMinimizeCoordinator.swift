import Observation
import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Brings the minimized tab bar — and the mini player docked into it — back
    /// after a short scroll up, instead of only when the page returns to its top.
    ///
    /// `UITabBarController.MinimizeBehavior` has no threshold to tune; the four
    /// public cases are the whole API, and UIKit drives `.onScrollDown` from a
    /// private scroll-away interaction whose reveal distance is long. Measured on
    /// iPhone 17 Pro / iOS 26.5: six separate ~60pt upward drags left the bar
    /// minimized, and only one ~440pt drag brought it back.
    ///
    /// So the reveal is driven from here. A pan recognizer on the tab bar
    /// controller's view finds the scroll view under the touch, and the distance
    /// is then measured on that scroll view's `contentOffset` — how far the
    /// content has travelled back up since its last reversal. Past
    /// `revealDistance` the declared behaviour flips to `.never`, which is what
    /// makes UIKit restore the full-size bar. It flips back to `.onScrollDown`
    /// once the user heads down again or the scroll settles, so the next downward
    /// scroll still minimizes it.
    ///
    /// The distance is deliberately measured on the content and not on the
    /// finger: a quick flick travels barely any distance under the thumb but
    /// coasts a long way, and measuring the finger left those flicks short of the
    /// threshold with the bar still minimized. Deceleration keeps changing
    /// `contentOffset` after the lift, so tracking the content covers the drag
    /// and its momentum with one threshold and no velocity guesswork.
    ///
    /// The flip runs without checking whether the bar is actually minimized,
    /// because nothing public reports that: `UITabBar`'s frame and origin and the
    /// container's bottom safe-area inset are all identical in both states. On an
    /// already-expanded bar the flip is a no-op beyond resetting UIKit's own
    /// distance accumulator, which only means the following scroll down gets a
    /// full threshold before minimizing again.
    @MainActor
    @Observable
    final class TabBarMinimizeCoordinator {
        static let shared = TabBarMinimizeCoordinator()

        /// How far the content must travel back up, in points, to bring the bar
        /// back. Measured on the scroll view rather than the finger, so a short
        /// flick counts for everything its deceleration carries — measuring the
        /// finger left quick flicks short of the threshold and the bar minimized.
        private static let revealDistance: CGFloat = 72

        /// Downward travel after a reveal that hands minimization back to UIKit.
        /// Without it, scrolling on past the reveal point would let the bar
        /// collapse again on the swipe that just asked for it.
        private static let rearmDistance: CGFloat = 24

        /// Quiet period after the last offset change that also hands minimization
        /// back, for a reveal the user never follows with a downward scroll.
        private static let settleDelay = Duration.milliseconds(350)

        private static let recognizerName = "Twinskaraoke.TabBarExpandOnScrollUp"

        enum Mode {
            /// UIKit's own behaviour: minimize once the user scrolls far enough down.
            case minimizesOnScrollDown
            /// Held only long enough to make UIKit restore the bar.
            case staysExpanded

            var swiftUI: TabBarMinimizeBehavior {
                switch self {
                case .minimizesOnScrollDown: .onScrollDown
                case .staysExpanded: .never
                }
            }

            var uiKit: UITabBarController.MinimizeBehavior {
                switch self {
                case .minimizesOnScrollDown: .onScrollDown
                case .staysExpanded: .never
                }
            }
        }

        /// Declared through `.tabBarMinimizeBehavior(_:)` rather than only assigned
        /// to the controller, because SwiftUI re-applies the declared value on
        /// every update and would otherwise overwrite a direct assignment.
        private(set) var mode: Mode = .minimizesOnScrollDown

        @ObservationIgnored private weak var tabBarController: UITabBarController?
        @ObservationIgnored private var gestureTarget: GestureTarget?
        @ObservationIgnored private weak var trackedScrollView: UIScrollView?
        @ObservationIgnored private var offsetObservation: NSKeyValueObservation?
        @ObservationIgnored private var rearmTask: Task<Void, Never>?
        @ObservationIgnored private var offsetPeak: CGFloat = 0
        @ObservationIgnored private var offsetTrough: CGFloat = 0
        @ObservationIgnored private var isHoldingExpanded = false

        private init() {}

        /// Installs the recognizer on the tab bar controller hosting `window`.
        /// Retries on later runloop turns: the SwiftUI view that calls this can
        /// reach its window before `TabView`'s backing controller is in place.
        func attach(to window: UIWindow, remainingAttempts: Int = 10) {
            guard tabBarController == nil else { return }
            guard let controller = Self.tabBarController(in: window.rootViewController) else {
                guard remainingAttempts > 0 else { return }
                Task { @MainActor [weak self] in
                    self?.attach(to: window, remainingAttempts: remainingAttempts - 1)
                }
                return
            }

            tabBarController = controller
            controller.tabBarMinimizeBehavior = mode.uiKit

            // The installer view can be re-added to the same controller — an iPad
            // resizing between the sidebar and tab shells does exactly that — and
            // a second recognizer on one view would double every measurement.
            let alreadyInstalled = controller.view.gestureRecognizers?.contains {
                $0.name == Self.recognizerName
            } ?? false
            guard !alreadyInstalled else { return }

            let target = GestureTarget { [weak self] recognizer in
                self?.handlePan(recognizer)
            }
            gestureTarget = target

            // `cancelsTouchesInView` off and simultaneous recognition on, so this
            // only ever watches the scroll gestures it sits above rather than
            // taking any touch away from them.
            let recognizer = UIPanGestureRecognizer(target: target, action: #selector(GestureTarget.handle(_:)))
            recognizer.name = Self.recognizerName
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = target
            controller.view.addGestureRecognizer(recognizer)
        }

        /// The pan is only used to find the scroll view under the touch and to
        /// reset the accumulator per gesture; the distance itself is measured on
        /// the scroll view, so a flick's deceleration counts as well as the drag.
        private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began, let view = recognizer.view else { return }
            guard let scrolled = Self.scrollView(under: recognizer.location(in: view), in: view) else { return }

            if scrolled !== trackedScrollView {
                trackedScrollView = scrolled
                offsetObservation = observeOffset(of: scrolled)
            }

            // Every gesture measures from its own reversal, including one that
            // lands on the scroll view already being watched. Leaving the extrema
            // in place carried a stale peak into the next gesture, where it
            // satisfied `revealDistance` on the very first offset change — even
            // one heading down, which flipped the bar out and straight back in.
            rearm()
            offsetPeak = scrolled.contentOffset.y
            offsetTrough = scrolled.contentOffset.y
        }

        /// Replaces any previous observation, so only one scroll view is ever
        /// watched. The change handler is `@Sendable`, so the offset comes out of
        /// the (Sendable) change rather than off the scroll view, and the hop is
        /// asserted rather than scheduled: `UIScrollView` mutates `contentOffset`
        /// on the main thread during both dragging and deceleration, and a `Task`
        /// hop here would land a frame late and out of order with the offsets it
        /// is accumulating.
        private func observeOffset(of scrollView: UIScrollView) -> NSKeyValueObservation {
            scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
                guard let offsetY = change.newValue?.y else { return }
                MainActor.assumeIsolated {
                    self?.trackOffset(offsetY)
                }
            }
        }

        private func trackOffset(_ offsetY: CGFloat) {
            offsetPeak = max(offsetPeak, offsetY)
            offsetTrough = min(offsetTrough, offsetY)

            if isHoldingExpanded {
                // Heading back down: hand minimization straight back, so the bar
                // can collapse again on the same swipe.
                guard offsetY - offsetTrough >= Self.rearmDistance else {
                    scheduleRearm()
                    return
                }
                rearm()
                offsetPeak = offsetY
            } else {
                guard offsetPeak - offsetY >= Self.revealDistance else { return }
                setMode(.staysExpanded)
                isHoldingExpanded = true
                offsetTrough = offsetY
                scheduleRearm()
            }
        }

        /// Hands minimization back once the scroll settles, so a reveal that is
        /// never followed by a downward scroll does not latch `.never` forever
        /// and leave the next scroll down unable to collapse the bar. Pushed out
        /// by every further offset change, so it lands after deceleration ends.
        private func scheduleRearm() {
            rearmTask?.cancel()
            rearmTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled else { return }
                self?.rearm()
            }
        }

        private func rearm() {
            rearmTask?.cancel()
            rearmTask = nil
            isHoldingExpanded = false
            setMode(.minimizesOnScrollDown)
        }

        /// The innermost vertically scrollable view under `location`. Innermost
        /// first so a horizontal carousel's own scroll view is skipped — it fails
        /// the height test — without also skipping the list it sits in.
        private static func scrollView(under location: CGPoint, in view: UIView) -> UIScrollView? {
            var candidate = view.hitTest(location, with: nil)
            while let current = candidate {
                if let scrollView = current as? UIScrollView,
                   scrollView.contentSize.height > scrollView.bounds.height
                {
                    return scrollView
                }
                candidate = current.superview
            }
            return nil
        }

        private func setMode(_ next: Mode) {
            guard mode != next else { return }
            mode = next
            // Also set it directly, so the bar moves on this touch rather than a
            // frame later when SwiftUI re-renders. The declared
            // `.tabBarMinimizeBehavior(_:)` then re-applies the identical value.
            tabBarController?.tabBarMinimizeBehavior = next.uiKit
        }

        private static func tabBarController(in controller: UIViewController?) -> UITabBarController? {
            guard let controller else { return nil }
            if let tabBarController = controller as? UITabBarController { return tabBarController }
            for child in controller.children {
                if let found = tabBarController(in: child) { return found }
            }
            return tabBarController(in: controller.presentedViewController)
        }
    }

    /// `UIGestureRecognizer` needs an `NSObject` target and delegate, which
    /// `@Observable` cannot be.
    private final class GestureTarget: NSObject, UIGestureRecognizerDelegate {
        private let onPan: (UIPanGestureRecognizer) -> Void

        init(onPan: @escaping (UIPanGestureRecognizer) -> Void) {
            self.onPan = onPan
        }

        @objc func handle(_ recognizer: UIPanGestureRecognizer) {
            onPan(recognizer)
        }

        nonisolated func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    /// Reaches the window so the coordinator can find the tab bar controller.
    struct TabBarMinimizeInstaller: UIViewRepresentable {
        func makeUIView(context _: Context) -> UIView {
            InstallerView()
        }

        func updateUIView(_: UIView, context _: Context) {}
    }

    private final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            TabBarMinimizeCoordinator.shared.attach(to: window)
        }
    }
#endif
