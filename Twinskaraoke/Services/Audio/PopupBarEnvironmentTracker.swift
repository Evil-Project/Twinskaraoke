import LNPopupUI
import Observation
import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Tracks whether the mini player is currently laid out inline with a
    /// minimized tab bar, so its bar style can follow.
    ///
    /// LNPopupController picks the bar height from the bar *style* alone —
    /// `_LNPopupBarHeightForPopupBar` switches on the resolved style and never
    /// consults the environment — so going inline does not shrink the bar on its
    /// own. Its documentation says as much: the framework reports the change
    /// through the `LNPopupBar.EnvironmentTrait` and leaves reacting to it to the
    /// app.
    ///
    /// Both heights are wanted here: `.floating` (58pt) matches the full-size tab
    /// bar, `.floatingCompact` (48pt) matches the minimized row the bar merges
    /// into.
    @MainActor
    @Observable
    final class PopupBarEnvironmentTracker {
        static let shared = PopupBarEnvironmentTracker()

        /// True while the bar sits inline with the collapsed tab bar.
        private(set) var isInline = false

        @ObservationIgnored private weak var observedBar: LNPopupBar?
        @ObservationIgnored private var registration: (any UITraitChangeRegistration)?

        private init() {}

        /// The style the bar should currently use. Declared through
        /// `.popupBarStyle(_:)` rather than assigned to the bar directly, because
        /// LNPopupUI re-applies the declared style on every popup state update
        /// and would otherwise overwrite a direct assignment.
        var barStyle: LNPopupBar.Style {
            isInline ? .floatingCompact : .floating
        }

        /// Starts observing `popupBar`. Safe to call repeatedly — the popup bar
        /// customizer runs on every popup update, and re-registering would stack
        /// observers on the same bar.
        func observe(_ popupBar: LNPopupBar) {
            guard observedBar !== popupBar else { return }
            observedBar = popupBar
            registration = nil

            apply(popupBar)
            registration = popupBar.registerForTraitChanges(
                [LNPopupBar.EnvironmentTrait.self]
            ) { (bar: LNPopupBar, _: UITraitCollection) in
                PopupBarEnvironmentTracker.shared.apply(bar)
            }
        }

        private func apply(_ popupBar: LNPopupBar) {
            let nowInline = popupBar.traitCollection.popupBarEnvironment == .inline
            guard isInline != nowInline else { return }
            isInline = nowInline

            // Also set the bar directly. LNPopupController flips the trait from
            // inside the property animator that runs its minimize transition, so
            // assigning here lets the height change ride that same animation
            // instead of landing a frame later when SwiftUI re-renders. The
            // declared `.popupBarStyle(_:)` then re-applies the identical value.
            popupBar.barStyle = barStyle
        }
    }
#endif
