import SwiftUI

/// Frozen release geometry prevents native accessory layout updates from
/// moving the destination underneath an in-flight closing animation.
enum PlayerClosingGeometry {
    struct Transition {
        let canvas: CGSize
        let surface: CGRect
        let artwork: CGRect
        let pill: CGRect
        let thumbnail: CGRect
    }

    struct Frame {
        let surface: CGRect
        let artwork: CGRect
        let cornerRadius: CGFloat
        let backgroundOpacity: Double
    }

    static let duration: TimeInterval = 0.5

    static func frame(_ transition: Transition, phase: Double) -> Frame {
        let t = min(1, max(0, phase))
        // Continuous curves over the entire duration: no phase boundaries,
        // clipped sine pulse, or motionless tail before the image handoff.
        let travel = 1 - pow(1 - t, 3)
        var surface = interpolate(transition.surface, transition.pill, travel)
        var artwork = interpolate(transition.artwork, transition.thumbnail, travel)
        let start = CGPoint(x: transition.artwork.midX, y: transition.artwork.midY)
        let end = CGPoint(x: transition.thumbnail.midX, y: transition.thumbnail.midY)
        let control1 = CGPoint(x: start.x + (end.x - start.x) * 0.65 + 12,
                               y: start.y + (end.y - start.y) * 0.65 + 40)
        let control2 = CGPoint(x: end.x + 12, y: end.y + 40)
        let u = 1 - pow(1 - t, 2)
        let v = 1 - u
        let center = CGPoint(
            x: v * v * v * start.x + 3 * v * v * u * control1.x + 3 * v * u * u * control2.x + u * u * u * end.x,
            y: v * v * v * start.y + 3 * v * v * u * control1.y + 3 * v * u * u * control2.y + u * u * u * end.y)
        artwork.origin = CGPoint(x: center.x - artwork.width / 2, y: center.y - artwork.height / 2)

        // Grow the lower edge around the dipping cover. The image and its
        // shadow remain inside one rounded player surface throughout landing.
        let padding = min(8, max(0, (transition.pill.height - transition.thumbnail.height) / 2))
        let top = min(surface.minY, artwork.minY - padding)
        let bottom = max(surface.maxY, artwork.maxY + padding)
        surface = CGRect(x: surface.minX, y: top, width: surface.width, height: bottom - top)
        return Frame(
            surface: surface, artwork: artwork,
            cornerRadius: min(transition.pill.height / 2, 28) * travel,
            // The native pill owns the background during the final return.
            // Only the cover continues moving; no tinted replica lingers in it.
            backgroundOpacity: 1 - smooth((t - 0.18) / 0.4)
        )
    }

    private static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private static func interpolate(_ from: CGRect, _ to: CGRect, _ t: Double) -> CGRect {
        CGRect(x: from.minX + (to.minX - from.minX) * t,
               y: from.minY + (to.minY - from.minY) * t,
               width: from.width + (to.width - from.width) * t,
               height: from.height + (to.height - from.height) * t)
    }
}

private struct PlayerClosingContentOpacityKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    var playerClosingContentOpacity: Double {
        get { self[PlayerClosingContentOpacityKey.self] }
        set { self[PlayerClosingContentOpacityKey.self] = newValue }
    }
}

/// Animatable evaluation is important: calculating just the endpoint frames in
/// a normal View would produce a straight interpolation and lose the dip.
struct PlayerClosingSettlement: ViewModifier, Animatable {
    let transition: PlayerClosingGeometry.Transition?
    var phase: Double
    let canvas: CGSize
    let normalOffset: CGFloat
    let image: UIImage?

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let frame = transition.map { PlayerClosingGeometry.frame($0, phase: phase) }
        let surface = frame?.surface ?? CGRect(x: 0, y: normalOffset, width: canvas.width, height: canvas.height)
        let scale = surface.width / max(1, canvas.width)
        content
            // This environment changes once at release, not every frame. The
            // full player fades its controls with a normal opacity animation.
            .environment(\.playerClosingContentOpacity, transition == nil ? 1 : 0)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: surface.width, height: surface.height, alignment: .topLeading)
            .opacity(frame?.backgroundOpacity ?? 1)
            .overlay(alignment: .topLeading) {
                if let frame, let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: frame.artwork.width, height: frame.artwork.height)
                        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero + (AM.Radius.thumb - AM.Radius.hero) * phase))
                        .shadow(color: .black.opacity(0.16 * (1 - phase)), radius: 12 * (1 - phase), y: 6 * (1 - phase))
                        .background {
                            #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("-UITestPlayerTracking") {
                                PlayerLandingArtworkProbe()
                            }
                            #endif
                        }
                        .position(x: frame.artwork.midX - surface.minX, y: frame.artwork.midY - surface.minY)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: frame?.cornerRadius ?? 0, style: .continuous))
            .offset(x: surface.minX, y: surface.minY)
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

}
