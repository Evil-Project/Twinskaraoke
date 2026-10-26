import SwiftUI

extension View {
    /// Aligns a horizontal shelf to its cards while retaining an inset at both ends.
    /// The shelf's stack must declare `scrollTargetLayout()`.
    func musicShelfScrolling(horizontalMargin: CGFloat = AM.Spacing.screenMargin) -> some View {
        contentMargins(.horizontal, horizontalMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .smoothScrolling()
    }

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
private struct ScrollEdgeHapticModifier: ViewModifier {
    let threshold: CGFloat
    let rearmDistance: CGFloat
    @State private var isArmed = true
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
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            let remaining = travel - offset
            if remaining <= threshold { return .atEnd }
            return remaining > rearmDistance ? .away : .approaching
        } action: { _, zone in
            switch zone {
            case .atEnd:
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
        content
            .scrollBounceBehavior(bounceBehavior)
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase, _ in
                ScrollPerformanceState.shared.update(id: scrollID, isScrolling: phase.isScrolling)
            }
            .onDisappear {
                ScrollPerformanceState.shared.update(id: scrollID, isScrolling: false)
            }
    }
}
