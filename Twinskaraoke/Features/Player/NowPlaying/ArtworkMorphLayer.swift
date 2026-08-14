import SwiftUI

/// The artwork in flight between the mini player and the full player.
///
/// Both real artworks hide while this is up and it stands in for them, so what
/// the eye follows is one continuous object rather than a thumbnail vanishing
/// as a large image appears somewhere else.
///
/// It is driven by the same `progress` the drag writes, which is the whole
/// reason it is drawn by hand rather than handed to `matchedGeometryEffect`:
/// that animates *between states*, on its own clock, so it cannot follow a
/// finger that is still moving — or reverse when someone changes their mind
/// halfway down. The library this replaces solved the same problem with a
/// private `_UIPortalView` mirrored into the window, which is the only way to
/// morph across a view-hierarchy boundary in UIKit. Inside one SwiftUI tree
/// there is no boundary to cross, so two measured rects and a lerp will do.
struct ArtworkMorphLayer: View {
    let image: UIImage
    let from: CGRect
    let to: CGRect
    let progress: Double
    /// The full player shrinks its artwork while paused. The measured frame is
    /// the layout one and does not know about that, so the morph would land at
    /// full size and the real artwork would pop down to meet it.
    let targetScale: CGFloat

    var body: some View {
        let rect = Geometry.rect(from: from, to: to, progress: progress, targetScale: targetScale)

        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: rect.width, height: rect.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Geometry.cornerRadius(progress: progress),
                    style: .continuous
                )
            )
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The interpolation, kept separate from the view so it can be checked
    /// without a screen. A morph is hard to eyeball — it is on screen for
    /// about half a second — and the failure modes are silent: an inverted
    /// rect, a corner radius running the wrong way, artwork flying in from the
    /// origin because a frame was still `.zero`.
    enum Geometry {
        static func rect(
            from: CGRect, to: CGRect, progress: Double, targetScale: CGFloat
        ) -> CGRect {
            let target = to.scaled(by: targetScale)
            let width = lerp(from.width, target.width, progress)
            let height = lerp(from.height, target.height, progress)
            let midX = lerp(from.midX, target.midX, progress)
            let midY = lerp(from.midY, target.midY, progress)
            return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
        }

        static func cornerRadius(progress: Double) -> CGFloat {
            lerp(AM.Radius.thumb, AM.Radius.hero, progress)
        }

        private static func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: Double) -> CGFloat {
            start + (end - start) * CGFloat(progress)
        }
    }
}

private extension CGRect {
    /// Scaled about its own centre, so the artwork shrinks in place rather
    /// than towards the origin.
    func scaled(by scale: CGFloat) -> CGRect {
        CGRect(
            x: midX - width * scale / 2,
            y: midY - height * scale / 2,
            width: width * scale,
            height: height * scale
        )
    }
}
