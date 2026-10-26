import SwiftUI
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

    private var needsDismissalGuard: Bool {
        if #available(iOS 27, *) { return true }
        return !reduceMotion
    }

    var body: some View {
        NavigationLink {
            // Deferred, so a grid of links does not build every destination
            // (and its view model) on each pass of the grid.
            DeferredView(destination)
                .zoomTransitionDestination(
                    id: id,
                    in: namespace,
                    isEnabled: !reduceMotion
                )
                // Keeps the push off iOS 26's broken interactive-pop path; see
                // ZoomPushDismissal for the defect and what it costs.
                .zoomPushDismissal(isEnabled: needsDismissalGuard)
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .zoomTransitionSource(id: id, in: namespace, isEnabled: !reduceMotion)
    }
}

extension View {
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
