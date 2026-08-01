import SwiftUI

struct EqualizerBars: View {
    let isAnimating: Bool
    @Environment(\.appReduceMotion) private var reduceMotion
    private let scrollState = ScrollPerformanceState.shared
    @State private var startDate = Date()
    @State private var isVisible: Bool = false

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width / 5
            TimelineView(
                .animation(
                    minimumInterval: DisplayRefreshRate.decorativeAnimationInterval,
                    paused: !shouldAnimateBars
                )
            ) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startDate))
                HStack(alignment: .bottom, spacing: barWidth / 2) {
                    ForEach(0 ..< 3) { i in
                        Capsule()
                            .fill(Color.appAccent)
                            .frame(
                                width: barWidth,
                                height: barHeight(for: i, total: geo.size.height, elapsed: elapsed)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .onAppear {
            isVisible = true
            startDate = Date()
        }
        .onDisappear { isVisible = false }
        .onChange(of: isAnimating) { _, new in
            if new { startDate = Date() }
        }
    }

    private func barHeight(for index: Int, total: CGFloat, elapsed: TimeInterval) -> CGFloat {
        guard shouldAnimateBars else { return total * 0.3 }
        let speeds: [Double] = [3.4, 2.7, 4.1]
        let offsets: [Double] = [0.0, 0.45, 0.9]
        let v = (sin(elapsed * speeds[index] + offsets[index] * .pi * 2) + 1) / 2
        return total * (0.3 + 0.7 * v)
    }

    private var shouldAnimateBars: Bool {
        isAnimating && isVisible && !reduceMotion && !scrollState.isScrolling
    }
}
