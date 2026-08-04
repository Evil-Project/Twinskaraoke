import SwiftUI

/// A `NavigationLink` whose destination zooms out of its own label, the way
/// Apple Music opens an album from a grid tile: the artwork lifts out of the
/// cell and expands into the detail view, and a drag-down mid-push tracks the
/// finger straight back into the cell it came from.
///
/// The interactive, interruptible dismissal is the reason this uses the system
/// transition rather than `matchedGeometryEffect` — a hand-rolled morph animates
/// correctly but cannot be dragged back, so its dismissal reads as a canned
/// reverse instead of direct manipulation.
///
/// **The namespace must outlive the cells that use it.** An earlier version
/// owned a private `@Namespace` per link, which reads as tidier and is wrong:
/// the namespace then lives inside the lazy grid cell, so when that cell is
/// rebuilt or discarded while the detail view is open, the source registration
/// dies with it. UIKit then logs "Dismissing a zoom transition to a view not in
/// the view hierarchy will trigger a fallback transition" and returns with the
/// wrong animation.
///
/// In practice that means declaring it on the view that owns the `ForEach`, not
/// inside the row. Declaring it on the view that owns the `NavigationStack` and
/// threading it down — as `LibraryView` does for `PlaylistsGridScreen` — is
/// stricter and safer still, and is the pattern to prefer for anything that
/// might be reused in a lazily-rebuilt context.
///
/// Uniqueness is the *ID's* job — pass the model's id, and scope it further if
/// one screen can show the same model twice.
///
/// Use this only where the label and the destination share a piece of artwork.
/// Zooming out of a chevron or a text row has nothing to morph and reads worse
/// than the standard push, so those call sites stay on `NavigationLink`.
///
/// Two further constraints, both learned on device — neither is cosmetic:
///
/// - **Vertical pulls belong to the destination — but only while
///   `ZoomPushDismissal` is in place.** A push's interactive dismissal is an
///   *edge* pan, so a downward pull does not compete with it, which is what lets
///   `PlaylistDetailView` reveal its search field by pulling. That holds only
///   because `zoomPushDismissal` suppresses the interactive pop entirely. If
///   that workaround is ever deleted — and its own documentation says to delete
///   it once Apple fixes the transition — re-check this: a restored interactive
///   dismissal, or any move to a modal presentation, reintroduces a vertical
///   drag-dismiss that will fight the pull and usually win.
/// - **Mind the source screen's navigation bar.** Zoom deliberately leaves the
///   source on screen, so any bar difference between the two screens animates in
///   full view instead of being carried off by a slide. A large title has to
///   collapse when its screen pushes, which reads as the header sliding away and
///   springing back; inline titles have nothing to animate.
struct ZoomNavigationLink<Destination: View, Label: View>: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    private let id: AnyHashable
    private let namespace: Namespace.ID
    private let destination: () -> Destination
    private let label: () -> Label

    init(
        id: some Hashable,
        in namespace: Namespace.ID,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.id = AnyHashable(id)
        self.namespace = namespace
        self.destination = destination
        self.label = label
    }

    var body: some View {
        NavigationLink {
            destination()
                .zoomTransitionDestination(
                    id: id,
                    in: namespace,
                    isEnabled: !reduceMotion
                )
                // Keeps the push off iOS 26's broken interactive-pop path; see
                // ZoomPushDismissal for the defect and what it costs.
                .zoomPushDismissal(isEnabled: !reduceMotion)
        } label: {
            label()
        }
        .zoomTransitionSource(id: id, in: namespace, isEnabled: !reduceMotion)
    }
}

extension View {
    /// Marks this view as the shape a zooming destination should grow out of.
    ///
    /// Gated on the app's own reduce-motion preference, not just the system
    /// one: `appReduceMotion` combines the accessibility setting with the
    /// in-app toggle, and the system transition only knows about the former.
    @ViewBuilder
    func zoomTransitionSource(
        id: some Hashable,
        in namespace: Namespace.ID,
        isEnabled: Bool
    ) -> some View {
        if isEnabled {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomTransitionDestination(
        id: some Hashable,
        in namespace: Namespace.ID,
        isEnabled: Bool
    ) -> some View {
        if isEnabled {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
