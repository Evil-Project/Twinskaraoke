import SwiftUI
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var speed: CGFloat = 35
    var gap: CGFloat = 48
    var startDelay: Double = 1.2
    var isPaused: Bool = false

    @Environment(\.appReduceEffects) private var reduceEffects
    @Environment(\.appAnimationsActive) private var animationsActive
    private let scrollState = ScrollPerformanceState.shared
    @State private var textSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    @State private var isVisible = false
    @State private var startDate = Date()

    private var needsScroll: Bool {
        !reduceEffects && containerWidth > 0 && textSize.width > containerWidth + 0.5
    }

    private var isScrolling: Bool {
        needsScroll
            && isVisible
            && animationsActive
            && !isPaused
            && !scrollState.isScrolling
    }
    private var travel: CGFloat {
        textSize.width + gap
    }

    private var scrollDuration: TimeInterval {
        Double(travel) / Double(max(1, speed))
    }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                ZStack(alignment: .leading) {
                    if needsScroll {
                        TimelineView(
                            .animation(
                                minimumInterval: DisplayRefreshRate.decorativeAnimationInterval,
                                paused: !isScrolling
                            )
                        ) { context in
                            HStack(spacing: gap) {
                                copy
                                copy
                            }
                            .offset(x: -phase(at: context.date))
                        }
                    } else {
                        copy
                    }
                }
                .accessibilityHidden(true)
                .frame(width: containerWidth > 0 ? containerWidth : nil, alignment: .leading)
                .mask(
                    LinearGradient(
                        stops: needsScroll
                            ? [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.04),
                                .init(color: .black, location: 0.96),
                                .init(color: .clear, location: 1),
                            ]
                            : [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 1),
                            ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipped()
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                guard abs(containerWidth - newWidth) > 0.5 else { return }
                containerWidth = newWidth
                restartCycle()
            }
            .background(
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        guard abs(textSize.width - size.width) > 0.5 else { return }
                        textSize = size
                        restartCycle()
                    }
            )
            .onChange(of: text) {
                restartCycle()
            }
            .onChange(of: reduceEffects) { _, shouldReduce in
                if !shouldReduce { restartCycle() }
            }
            .onChange(of: isPaused) { _, paused in
                if !paused { restartCycle() }
            }
            .onChange(of: animationsActive) { _, active in
                if active { restartCycle() }
            }
            .onChange(of: scrollState.isScrolling) { _, scrolling in
                if !scrolling { restartCycle() }
            }
            .onAppear {
                isVisible = true
                restartCycle()
            }
            .onDisappear {
                isVisible = false
            }
    }
    private var copy: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.opacity)
            .fixedSize()
    }

    private func phase(at date: Date) -> CGFloat {
        Self.phase(
            elapsed: date.timeIntervalSince(startDate),
            travel: travel,
            scrollDuration: scrollDuration,
            startDelay: startDelay
        )
    }

    private func restartCycle() {
        startDate = Date()
    }
    nonisolated static func phase(
        elapsed: TimeInterval,
        travel: CGFloat,
        scrollDuration: TimeInterval,
        startDelay: TimeInterval
    ) -> CGFloat {
        guard travel > 0, scrollDuration > 0 else { return 0 }
        let dwell = max(0, startDelay)
        let cycle = dwell + scrollDuration
        let position = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
        guard position > dwell else { return 0 }
        return travel * CGFloat((position - dwell) / scrollDuration)
    }
}
