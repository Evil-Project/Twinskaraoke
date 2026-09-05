import CoreGraphics
import Testing
@testable import Twinskaraoke

struct PlayerClosingGeometryTests {
    private func transition(width: CGFloat = 390, height: CGFloat = 844, release: CGFloat = 200) -> PlayerClosingGeometry.Transition {
        PlayerClosingGeometry.Transition(
            canvas: CGSize(width: width, height: height),
            surface: CGRect(x: 0, y: release, width: width, height: height),
            artwork: CGRect(x: 40, y: release + 160, width: 300, height: 300),
            pill: CGRect(x: 21, y: height - 144, width: width - 42, height: 58),
            thumbnail: CGRect(x: 33, y: height - 135, width: 40, height: 40)
        )
    }

    @Test func startsAtReleaseAndLandsExactlyOnNativePill() {
        let flight = transition()
        let start = PlayerClosingGeometry.frame(flight, phase: 0)
        #expect(start.surface == flight.surface)
        #expect(start.artwork == flight.artwork)
        #expect(start.backgroundOpacity == 1)
        let end = PlayerClosingGeometry.frame(flight, phase: 1)
        #expect(end.surface == flight.pill)
        #expect(end.artwork == flight.thumbnail)
        #expect(end.backgroundOpacity == 0)
    }

    @Test func coverDipsRightAndBelowThumbnailThenReturnsBeforeHandoff() {
        let flight = transition()
        let dip = PlayerClosingGeometry.frame(flight, phase: 0.72)
        #expect(dip.artwork.midX > flight.thumbnail.midX + 3)
        #expect(dip.artwork.midY > flight.thumbnail.midY + 3)
        let settled = PlayerClosingGeometry.frame(flight, phase: 0.9)
        #expect(settled.artwork.midY > flight.thumbnail.midY)
        #expect(settled.artwork.midY < dip.artwork.midY)
        #expect(settled.artwork.midX < dip.artwork.midX)
        #expect(settled.backgroundOpacity == 0)
        let almostLanded = PlayerClosingGeometry.frame(flight, phase: 0.99)
        #expect(almostLanded.artwork.midY < settled.artwork.midY)
        #expect(abs(almostLanded.artwork.midY - flight.thumbnail.midY) < 0.02)
    }

    @Test func backgroundClearsBeforeFinalArtworkReturn() {
        let flight = transition()
        for step in 60...100 {
            #expect(PlayerClosingGeometry.frame(flight, phase: Double(step) / 100).backgroundOpacity == 0)
        }
    }

    @Test func artworkVelocityHasNoPhaseBoundaryOrAbruptStop() {
        let flight = transition()
        let dt = 0.0001
        for t in [0.35, 0.58, 0.72, 0.82, 0.88, 0.9, 1.0] {
            let before = PlayerClosingGeometry.frame(flight, phase: t - dt).artwork.midY
            let at = PlayerClosingGeometry.frame(flight, phase: t).artwork.midY
            let after = PlayerClosingGeometry.frame(flight, phase: t + dt).artwork.midY
            #expect(abs((after - at) / dt - (at - before) / dt) < 2)
        }
    }

    @Test func surfaceContainsCoverThroughoutDifferentReleasePositions() {
        for release: CGFloat in [0, 150, 400, 780] {
            let flight = transition(release: release)
            for step in 0...100 {
                let value = PlayerClosingGeometry.frame(flight, phase: Double(step) / 100)
                #expect(value.surface.insetBy(dx: -0.001, dy: -0.001).contains(value.artwork))
                #expect(value.surface.width > 0 && value.surface.height > 0)
                #expect(value.artwork.width >= 40)
            }
        }
    }

    @Test func destinationSupportsInlineAndSidebarPills() {
        for pill in [CGRect(x: 85, y: 700, width: 220, height: 48),
                     CGRect(x: 8, y: 1000, width: 300, height: 58)] {
            let base = transition()
            let flight = PlayerClosingGeometry.Transition(canvas: base.canvas, surface: base.surface,
                artwork: base.artwork, pill: pill,
                thumbnail: CGRect(x: pill.minX + 12, y: pill.midY - 15, width: 30, height: 30))
            let end = PlayerClosingGeometry.frame(flight, phase: 1)
            #expect(end.surface == pill)
            #expect(end.artwork == flight.thumbnail)
        }
    }
}
