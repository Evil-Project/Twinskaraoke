import CoreGraphics
import Testing
@testable import Twinskaraoke

/// The artwork that flies between the mini player and the full player is on
/// screen for about half a second, which is not long enough to catch an
/// inverted rect or a corner radius running the wrong way by eye.
@Suite("Artwork morph geometry")
struct ArtworkMorphGeometryTests {
    /// A 40pt thumbnail near the bottom of the screen, and a 340pt cover
    /// roughly where the player puts it.
    private let bar = CGRect(x: 24, y: 780, width: 40, height: 40)
    private let player = CGRect(x: 27, y: 180, width: 340, height: 340)

    private func rect(_ progress: Double) -> CGRect {
        ArtworkMorphLayer.Geometry.rect(from: bar, to: player, progress: progress)
    }

    @Test("At rest collapsed, it sits exactly on the mini player's artwork")
    func startsOnTheBar() {
        let start = rect(0)
        #expect(abs(start.midX - bar.midX) < 0.001)
        #expect(abs(start.midY - bar.midY) < 0.001)
        #expect(abs(start.width - bar.width) < 0.001)
    }

    @Test("At rest open, it sits exactly on the player's artwork")
    func endsOnThePlayer() {
        let end = rect(1)
        #expect(abs(end.midX - player.midX) < 0.001)
        #expect(abs(end.midY - player.midY) < 0.001)
        #expect(abs(end.width - player.width) < 0.001)
    }

    /// The target rect is taken exactly as measured, with no scaling of its
    /// own. `GeometryProxy.frame(in: .global)` reports the *rendered* rect, so
    /// the player's paused `scaleEffect` is already in it — measured at 304.5pt
    /// for a 346pt artwork. An earlier version applied that 0.88 a second time
    /// here and shrank the target twice.
    @Test("The measured target is honoured exactly, with no scaling of its own")
    func doesNotRescaleTheTarget() {
        let end = rect(1)
        #expect(abs(end.width - player.width) < 0.001)
        #expect(abs(end.height - player.height) < 0.001)
        #expect(abs(end.midX - player.midX) < 0.001)
        #expect(abs(end.midY - player.midY) < 0.001)
    }

    @Test("It travels monotonically, without overshooting either end")
    func travelsMonotonically() {
        var previousY = rect(0).midY
        var previousWidth = rect(0).width
        for step in 1...20 {
            let current = rect(Double(step) / 20)
            #expect(current.midY < previousY, "expected upward travel at step \(step)")
            #expect(current.width > previousWidth, "expected growth at step \(step)")
            #expect(current.width <= player.width + 0.001)
            #expect(current.midY >= player.midY - 0.001)
            previousY = current.midY
            previousWidth = current.width
        }
    }

    @Test("The corner radius runs from the thumbnail's to the cover's")
    func cornerRadiusInterpolates() {
        #expect(ArtworkMorphLayer.Geometry.cornerRadius(progress: 0) == AM.Radius.thumb)
        #expect(ArtworkMorphLayer.Geometry.cornerRadius(progress: 1) == AM.Radius.hero)
        let midpoint = ArtworkMorphLayer.Geometry.cornerRadius(progress: 0.5)
        #expect(midpoint > AM.Radius.thumb && midpoint < AM.Radius.hero)
    }
}
