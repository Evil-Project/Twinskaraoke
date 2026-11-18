import SwiftUI

/// The ring around the player's translate button while a translation runs.
///
/// Paused while the full-screen player is closed (it stays mounted off
/// screen), while the app is not active and once the ring has gone; before,
/// it redrew at the full display rate behind the rest of the app for as long
/// as a translation took.
struct LyricsTranslationSpinner: View {
    var isPaused = false
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        if reduceMotion {
            Circle()
                .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(3)
        } else {
            TimelineView(
                .animation(
                    minimumInterval: DisplayRefreshRate.lightweightAnimationInterval,
                    paused: !shouldSpin
                )
            ) { context in
                Circle()
                    .trim(from: 0, to: 0.82)
                    .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(Self.degrees(at: context.date)))
                    .padding(3)
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
        }
    }

    private var shouldSpin: Bool {
        Self.shouldSpin(isPaused: isPaused, isVisible: isVisible, scenePhase: scenePhase)
    }

    static func shouldSpin(isPaused: Bool, isVisible: Bool, scenePhase: ScenePhase) -> Bool {
        !isPaused && isVisible && scenePhase == .active
    }

    private static func degrees(at date: Date) -> Double {
        let cycle = 1.12
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return phase * 360 - 90
    }
}
