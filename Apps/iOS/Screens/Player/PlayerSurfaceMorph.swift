import SwiftUI

/// How the compact player switches between its artwork and lyrics surfaces.
/// The large artwork travels into the lyrics header's thumbnail and back, and
/// the title block travels with it to the header text, while the two surfaces
/// themselves only fade. A move on the surfaces would drag the matched
/// children off their path.
///
/// Only Reduce Motion turns the morph off; Low Power Mode does not, because
/// `appReduceEffects` is for perpetual decoration and this is an interaction.
/// The reduced path still fades, so the switch is never a hard cut.
enum PlayerSurfaceMorph {
    enum Element: Hashable { case artwork, nowPlayingText }
    enum Surface { case artwork, lyrics }
    enum Style: Equatable { case morph, crossFade }

    static func style(reduceMotion: Bool) -> Style {
        reduceMotion ? .crossFade : .morph
    }

    /// The iPad layouts have no lyrics header and pass no namespace, so nothing
    /// there is matched, including across a rotation into the compact layout.
    static func matchesGeometry(style: Style, hasNamespace: Bool) -> Bool {
        style == .morph && hasNamespace
    }

    static func animation(for style: Style) -> Animation {
        switch style {
        case .morph: AppMotion.standard
        case .crossFade: AppMotion.crossFade
        }
    }

    static func transition(for _: Surface, style _: Style) -> AnyTransition {
        .opacity
    }
}

extension View {
    /// Matches this element across the two surfaces. Apply it before a fixed
    /// `.frame`, so only the content travels: the frame keeps its resting rect,
    /// layout doesn't reflow, and frame reporters outside it are unaffected.
    func playerSurfaceMorph(_ element: PlayerSurfaceMorph.Element, in namespace: Namespace.ID?) -> some View {
        modifier(PlayerSurfaceMorphModifier(element: element, namespace: namespace))
    }

    func playerSurfaceTransition(_ surface: PlayerSurfaceMorph.Surface) -> some View {
        modifier(PlayerSurfaceTransitionModifier(surface: surface))
    }
}

private struct PlayerSurfaceMorphModifier: ViewModifier {
    let element: PlayerSurfaceMorph.Element
    let namespace: Namespace.ID?
    @Environment(\.appReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let style = PlayerSurfaceMorph.style(reduceMotion: reduceMotion)
        if PlayerSurfaceMorph.matchesGeometry(style: style, hasNamespace: namespace != nil), let namespace {
            switch element {
            case .artwork:
                content.matchedGeometryEffect(id: element, in: namespace)
            case .nowPlayingText:
                // Position only: `MarqueeText` measures its width, and a size
                // change mid-flight would restart or clip its scroll. The two
                // texts cross-fade while they travel.
                content.matchedGeometryEffect(id: element, in: namespace, properties: .position, anchor: .leading)
            }
        } else {
            content
        }
    }
}

private struct PlayerSurfaceTransitionModifier: ViewModifier {
    let surface: PlayerSurfaceMorph.Surface
    @Environment(\.appReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(
            PlayerSurfaceMorph.transition(for: surface, style: PlayerSurfaceMorph.style(reduceMotion: reduceMotion))
        )
    }
}
