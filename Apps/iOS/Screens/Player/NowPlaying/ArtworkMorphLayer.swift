import SwiftUI

/// The artwork in flight when opening from the mini player.
///
/// The full artwork hides while this stands in for it. The mini thumbnail stays
/// visible underneath until the advancing player background covers it. The
/// morph itself is clipped inside that background, never above its top edge.
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
    let surfaceOffset: CGFloat
    /// The shadow the real artwork wears once it arrives, faded in across the
    /// flight. Without it the stand-in was flat and the shadow appeared to
    /// arrive a beat late — it was simply the moment the real artwork came
    /// back. A mini player thumbnail has no shadow, so scaling it with
    /// `progress` is also the honest interpolation between the two ends.
    let shadow: AM.ShadowStyle

    var body: some View {
        let rect = Geometry.rect(from: from, to: to, progress: progress, surfaceOffset: surfaceOffset)

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
            .shadow(
                color: shadow.color.opacity(progress),
                radius: shadow.radius * CGFloat(progress),
                y: shadow.y * CGFloat(progress)
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
        /// Frames already include the artwork's playback scale. The destination
        /// is measured inside the stationary player surface, excluding the
        /// presentation's offset so it cannot drift during the morph.
        static func rect(from: CGRect, to: CGRect, progress: Double, surfaceOffset: CGFloat = 0) -> CGRect {
            let width = lerp(from.width, to.width, progress)
            let height = lerp(from.height, to.height, progress)
            let midX = lerp(from.midX, to.midX, progress)
            let midY = lerp(from.midY, to.midY, progress)
            // Convert the original window-space path into the moving player's
            // coordinates. Its parent supplies both translation and clipping.
            return CGRect(x: midX - width / 2, y: midY - height / 2 - surfaceOffset, width: width, height: height)
        }

        static func cornerRadius(progress: Double) -> CGFloat {
            lerp(AM.Radius.thumb, AM.Radius.hero, progress)
        }

        private static func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: Double) -> CGFloat {
            start + (end - start) * CGFloat(progress)
        }
    }
}
