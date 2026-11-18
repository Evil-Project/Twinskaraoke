import SwiftUI

struct LyricsBouncingDots: View {
    let isActive: Bool
    var progress: Double?
    var dotSize: CGFloat = 9
    var color: Color = .primary
    /// For dots that stay mounted while nobody can see them, such as the
    /// lyrics of the closed full-screen player. A flag from the caller rather
    /// than a read here: this view also builds for watchOS, tvOS and macOS,
    /// which have no Now Playing presentation.
    var isPaused = false
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appReduceEffects) private var reduceEffects
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationClock = ActiveAnimationClock()
    @State private var isVisible = false
    private let loopCycle: TimeInterval = 1.6
    var body: some View {
        // The looping dots are perpetual decoration, so Low Power Mode and a
        // hot device stop them too. The progress-driven dots follow playback
        // instead and keep moving under those.
        if reduceMotion || (reduceEffects && !showsSyncedProgress) {
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
                    paused: !shouldAnimateLoop
                )
            ) { context in
                let t = animationClock.elapsed(at: context.date)
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
            .onAppear {
                isVisible = true
            }
            .onDisappear {
                isVisible = false
                animationClock.setRunning(false, at: .now)
            }
            .onChange(of: shouldAnimateLoop, initial: true) { _, running in
                animationClock.setRunning(running, at: .now)
            }
        }
    }

    private var showsSyncedProgress: Bool {
        progress != nil && isActive
    }

    private var shouldAnimateLoop: Bool {
        Self.shouldAnimateLoop(
            isActive: isActive,
            isPaused: isPaused,
            isVisible: isVisible,
            reduceEffects: reduceEffects,
            scenePhase: scenePhase
        )
    }

    /// The looping dots tick only while someone can see them move.
    static func shouldAnimateLoop(
        isActive: Bool,
        isPaused: Bool,
        isVisible: Bool,
        reduceEffects: Bool,
        scenePhase: ScenePhase
    ) -> Bool {
        isActive && !isPaused && isVisible && !reduceEffects && scenePhase == .active
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
        let riseStart = Double(i) * perDot
        let riseEnd = riseStart + perDot / 2
        let fallEnd = riseEnd + perDot / 2
        if t < riseStart { return 0.25 }
        if t < riseEnd {
            let local = (t - riseStart) / (perDot / 2)
            return 0.25 + 0.75 * local
        }
        if t < fallEnd {
            let local = (t - riseEnd) / (perDot / 2)
            return 1.0 - 0.75 * local
        }
        return 0.25
    }
}
