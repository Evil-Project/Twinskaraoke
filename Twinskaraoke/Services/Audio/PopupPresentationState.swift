import SwiftUI
import Observation

@MainActor
@Observable
final class PopupPresentationState {
    static let shared = PopupPresentationState()

    private(set) var isExpanded = false

    private init() {}

    func setExpanded(_ isExpanded: Bool) {
        self.isExpanded = isExpanded
    }

    func collapse() {
        setExpanded(false)
    }
}
