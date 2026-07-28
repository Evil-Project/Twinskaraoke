import SwiftUI

struct LyricsBouncingDots: View {
    let isActive: Bool
    var progress: Double?
    var dotSize: CGFloat = 9
    var color: Color = .primary
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var loopPhase: Date = .now
    private let loopCycle: TimeInterval = 1.6
    var body: some View {
        if reduceMotion {
            HStack(spacing: dotSize * 0.55) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .opacity(isActive ? 0.9 : 0.35)
                }
            }
        } else if let progress, isActive {
            HStack(spacing: dotSize * 0.55) {
                ForEach(0 ..< 3, id: \.self) { i in
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .opacity(syncedOpacity(for: i, progress: progress))
                        .scaleEffect(syncedScale(for: i, progress: progress))
                }
            }
            .animation(.easeOut(duration: 0.18), value: progress)
        } else {
            TimelineView(
                .animation(
                    minimumInterval: DisplayRefreshRate.lightweightAnimationInterval,
                    paused: !isActive
                )
            ) { context in
                let t = context.date.timeIntervalSince(loopPhase)
                    .truncatingRemainder(dividingBy: loopCycle)
                HStack(spacing: dotSize * 0.55) {
                    ForEach(0 ..< 3, id: \.self) { i in
                        Circle()
                            .fill(color)
                            .frame(width: dotSize, height: dotSize)
                            .opacity(loopOpacity(for: i, t: t))
                    }
                }
            }
        }
    }

    private func syncedOpacity(for i: Int, progress: Double) -> Double {
        let p = max(0, min(1, progress))
        let dotStart = Double(i) / 3.0
        let dotEnd = Double(i + 1) / 3.0
        if p <= dotStart { return 0.25 }
        if p >= dotEnd { return 1.0 }
        let local = (p - dotStart) / (dotEnd - dotStart)
        return 0.25 + 0.75 * local
    }

    private func syncedScale(for i: Int, progress: Double) -> CGFloat {
        let p = max(0, min(1, progress))
        let dotStart = Double(i) / 3.0
        let dotEnd = Double(i + 1) / 3.0
        if p <= dotStart { return 1.0 }
        if p >= dotEnd { return 1.18 }
        let local = (p - dotStart) / (dotEnd - dotStart)
        return 1.0 + 0.18 * CGFloat(local)
    }

    private func loopOpacity(for i: Int, t: TimeInterval) -> Double {
        guard isActive else { return 0.35 }
        let perDot = loopCycle / 4.0
        let start = Double(i) * perDot
        let end = start + perDot
        if t < start { return 0.25 }
        if t < end {
            let local = (t - start) / perDot
            return 0.25 + 0.75 * local
        }
        return 1.0
    }
}
