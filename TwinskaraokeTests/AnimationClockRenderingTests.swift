import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

@MainActor
@Observable
private final class EqualizerHostState {
    var showsBars = false
    var isAnimating = false
}

private struct EqualizerHost: View {
    let state: EqualizerHostState

    var body: some View {
        ZStack {
            Color.black
            if state.showsBars {
                EqualizerBars(isAnimating: state.isAnimating, pausesWhileScrolling: false)
                    .frame(width: 60, height: 60)
            }
        }
        .frame(width: 100, height: 100)
        .environment(\.scenePhase, .active)
    }
}

/// Rendered, not unit-level: the failure lived in how SwiftUI applied the
/// clock's state, which no test of the clock alone can see.
@MainActor
@Suite("Decorative animation clock rendering", .serialized)
struct AnimationClockRenderingTests {
    private func distinctFrames(after configure: (EqualizerHostState) async -> Void) async -> Int {
        let state = EqualizerHostState()
        let host = UIHostingController(rootView: EqualizerHost(state: state))
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try? await Task.sleep(for: .milliseconds(300))
        await configure(state)
        try? await Task.sleep(for: .milliseconds(600))
        var frames = Set<Data>()
        for _ in 0 ..< 5 {
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            frames.insert(image.pngData() ?? Data())
            try? await Task.sleep(for: .milliseconds(150))
        }
        return frames.count
    }

    @Test("Bars that appear while a song is already playing animate")
    func barsInsertedWhilePlayingAnimate() async {
        let frames = await distinctFrames { state in
            state.isAnimating = true
            state.showsBars = true
        }
        #expect(frames > 1)
    }

    @Test("Bars that start playing after they appear animate")
    func barsStartedAfterAppearingAnimate() async {
        let frames = await distinctFrames { state in
            state.showsBars = true
            try? await Task.sleep(for: .milliseconds(300))
            state.isAnimating = true
        }
        #expect(frames > 1)
    }
}
