import SwiftUI

extension View {
    func smoothScrolling(bounceBehavior: ScrollBounceBehavior = .basedOnSize) -> some View {
        modifier(SmoothScrollingModifier(bounceBehavior: bounceBehavior))
    }

    func collapsedNavigationTitle(
        _ isCollapsed: Binding<Bool>,
        threshold: CGFloat = 180
    ) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > threshold
        } action: { _, collapsed in
            guard isCollapsed.wrappedValue != collapsed else { return }
            isCollapsed.wrappedValue = collapsed
        }
    }

    /// Thumps once when the scroll view arrives at its bottom edge.
    ///
    /// Attach to long content lists, not to short ones: on content that barely
    /// overflows, the end is reached constantly and the feedback stops meaning
    /// anything.  The `guard` below skips non-scrolling content entirely.
    func scrollEdgeHaptic(threshold: CGFloat = 2, rearmDistance: CGFloat = 48) -> some View {
        modifier(ScrollEdgeHapticModifier(threshold: threshold, rearmDistance: rearmDistance))
    }

    func scrollParallaxHero(
        baseSize: CGFloat,
        restingOffset: CGFloat = 0,
        fadesWhenCollapsed: Bool = false,
        reduceMotion: Bool,
        pullDownOverride: CGFloat? = nil
    ) -> some View {
        visualEffect { content, proxy in
            let rawOffset = proxy.frame(in: .scrollView(axis: .vertical)).minY - restingOffset
            let pullDown = reduceMotion ? 0 : (pullDownOverride ?? max(0, rawOffset))
            let collapse = reduceMotion ? 0 : max(0, -rawOffset)
            let scale = max(
                140 / max(baseSize, 1),
                1 + (pullDown * 0.6 - collapse * 0.4) / max(baseSize, 1)
            )
            let yOffset = pullDown > 0 ? -pullDown / 2 : 0
            let opacity = fadesWhenCollapsed ? 1 - min(0.7, collapse / 250) : 1

            return content
                .scaleEffect(scale)
                .offset(y: yOffset)
                .opacity(opacity)
        }
    }
}

/// Thumps once on arrival at the bottom, then refuses to thump again until the
/// user has scrolled a real distance back up.
///
/// The hysteresis is the whole point.  A single `contentOffset >= travel`
/// comparison looks correct and misbehaves badly: a rubber-band bounce
/// oscillates across that line for the length of the bounce, so the thump
/// re-fires every frame of it instead of once on arrival.
private struct ScrollEdgeHapticModifier: ViewModifier {
    let threshold: CGFloat
    let rearmDistance: CGFloat
    @State private var isArmed = true

    /// Coarse zones rather than a raw distance.  `onScrollGeometryChange` only
    /// runs its action when the transformed value *changes*, so returning a
    /// continuously-varying `CGFloat` makes it fire every frame — SwiftUI then
    /// logs "tried to update multiple times per frame".  Three zones collapse a
    /// whole drag into two or three action calls.
    private enum Zone: Equatable {
        case atEnd
        case approaching
        case away
        case notScrollable
    }

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Zone.self) { geometry in
            let travel = geometry.contentSize.height
                + geometry.contentInsets.top
                + geometry.contentInsets.bottom
                - geometry.containerSize.height
            guard travel > 0 else { return .notScrollable }
            // Remaining distance to the bottom; negative while overscrolled.
            let remaining = travel - geometry.contentOffset.y
            if remaining <= threshold { return .atEnd }
            return remaining > rearmDistance ? .away : .approaching
        } action: { _, zone in
            switch zone {
            case .atEnd:
                // Re-arming requires reaching `.away`, so a rubber-band settle
                // that dips back into `.approaching` cannot re-trigger.
                guard isArmed else { return }
                isArmed = false
                AppHaptic.boundary.play()
            case .away:
                isArmed = true
            case .approaching, .notScrollable:
                break
            }
        }
    }
}

private struct SmoothScrollingModifier: ViewModifier {
    let bounceBehavior: ScrollBounceBehavior
    @State private var scrollID = UUID()

    func body(content: Content) -> some View {
        let configured = content
            .scrollBounceBehavior(bounceBehavior)
            .scrollDismissesKeyboard(.interactively)

        if #available(iOS 18.0, *) {
            configured
                .onScrollPhaseChange { _, phase in
                    ScrollPerformanceState.shared.update(id: scrollID, isScrolling: phase.isScrolling)
                }
                .onDisappear {
                    ScrollPerformanceState.shared.update(id: scrollID, isScrolling: false)
                }
        } else {
            configured
        }
    }
}
