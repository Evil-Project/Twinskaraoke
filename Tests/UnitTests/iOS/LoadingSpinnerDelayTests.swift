import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

/// Rendered: what matters is whether the spinner is on screen, and when.
@MainActor
@Suite("Loading spinner delay", .serialized)
struct LoadingSpinnerDelayTests {
    private static let frame = CGRect(x: 0, y: 0, width: 120, height: 120)

    /// Draws `view` over black after `wait`, as PNG data.
    private func render(_ view: some View, after wait: Duration) async -> Data {
        let host = UIHostingController(rootView: ZStack {
            Color.black
            view
        }
        .frame(width: Self.frame.width, height: Self.frame.height)
        .environment(\.colorScheme, .dark))
        let window = makeTestWindow(frame: Self.frame)
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try? await Task.sleep(for: wait)
        return draw(host)
    }

    private func draw(_ host: UIViewController) -> Data {
        UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }.pngData() ?? Data()
    }

    @Test func theSpinnerStaysOffScreenUntilItsDelayHasPassed() async {
        let empty = await render(Color.clear, after: .milliseconds(400))
        let waiting = await render(
            CenteredLoadingView(minHeight: 100, appearanceDelay: .seconds(30)),
            after: .milliseconds(400)
        )
        #expect(waiting == empty)
    }

    /// Polls for the spinner instead of trusting one fixed wait: on a busy
    /// machine the view's task and the next render can both run late.
    @Test func theSpinnerShowsOnceItsDelayHasPassed() async {
        let host = UIHostingController(rootView: ZStack {
            Color.black
            CenteredLoadingView(minHeight: 100, appearanceDelay: .milliseconds(50))
        }
        .frame(width: Self.frame.width, height: Self.frame.height)
        .environment(\.colorScheme, .dark))
        let window = makeTestWindow(frame: Self.frame)
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let empty = await render(Color.clear, after: .milliseconds(100))
        var shown = false
        for _ in 0 ..< 50 where !shown {
            try? await Task.sleep(for: .milliseconds(100))
            shown = draw(host) != empty
        }
        #expect(shown, "The spinner was not drawn within five seconds")
    }

    @Test func screensWaitAThirdOfASecond() {
        #expect(CenteredLoadingView.standardDelay == .milliseconds(300))
    }
}
