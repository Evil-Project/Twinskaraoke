import SwiftUI

/// Builds its content only when SwiftUI renders it, rather than when it is
/// constructed.
///
/// `NavigationLink(destination:)` and the closure form both build the
/// destination while the *link* is built, on every pass of the view that owns
/// the link. A destination whose `@State` starts out as a view model allocates
/// that model each time, and SwiftUI throws it away again: a `@State` initial
/// value is a plain expression, so only the instance from the push is kept.
/// That was a playlist view model per grid cell per Library update, an
/// `AuthManager` (with its three notification observers) per toolbar update on
/// every tab, and so on.
///
/// Wrapped in this, the link stores a closure, and the destination is built
/// when the push renders it.
struct DeferredView<Content: View>: View {
    private let build: () -> Content

    init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }

    var body: Content {
        build()
    }
}
