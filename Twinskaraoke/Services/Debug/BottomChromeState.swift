import SwiftUI
import Observation

@MainActor
@Observable
final class BottomChromeState {
    static let shared = BottomChromeState()

    private(set) var isCollapsed = false

    private let collapseThreshold: CGFloat = 36
    private let expandThreshold: CGFloat = 4

    private init() {}

    func updateScrollOffset(_ offset: CGFloat) {
        if offset > collapseThreshold {
            setCollapsed(true)
        } else if offset <= expandThreshold {
            setCollapsed(false)
        }
    }

    func expand() {
        setCollapsed(false)
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard isCollapsed != collapsed else { return }
        isCollapsed = collapsed
    }
}
