import SwiftUI
import Testing
@testable import Twinskaraoke

@Suite("Player artwork and lyrics morph")
struct PlayerSurfaceMorphTests {
    @Test("Switching surfaces morphs when motion is allowed")
    func morphsWhenMotionIsAllowed() {
        #expect(PlayerSurfaceMorph.style(reduceMotion: false) == .morph)
    }

    @Test("Reduce Motion turns the morph into a cross-fade")
    func crossFadesUnderReduceMotion() {
        #expect(PlayerSurfaceMorph.style(reduceMotion: true) == .crossFade)
    }

    @Test("A cross-fade matches no geometry, so nothing travels")
    func crossFadeMatchesNoGeometry() {
        #expect(!PlayerSurfaceMorph.matchesGeometry(style: .crossFade, hasNamespace: true))
        #expect(!PlayerSurfaceMorph.matchesGeometry(style: .crossFade, hasNamespace: false))
    }

    @Test("Layouts without a namespace, the iPad ones, match no geometry")
    func noNamespaceMatchesNoGeometry() {
        #expect(!PlayerSurfaceMorph.matchesGeometry(style: .morph, hasNamespace: false))
        #expect(PlayerSurfaceMorph.matchesGeometry(style: .morph, hasNamespace: true))
    }

    @Test("The morph rides the spring the surface switch already used")
    func morphUsesTheSurfaceSpring() {
        #expect(PlayerSurfaceMorph.animation(for: .morph) == AppMotion.standard)
    }

    @Test("Reduce Motion fades instead of cutting")
    func reducedPathFadesInsteadOfCutting() {
        let animation: Animation? = PlayerSurfaceMorph.animation(for: .crossFade)
        #expect(animation != nil)
        #expect(animation == AppMotion.crossFade)
    }
}
