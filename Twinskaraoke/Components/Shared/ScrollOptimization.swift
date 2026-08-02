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
