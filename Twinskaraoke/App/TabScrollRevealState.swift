import SwiftUI
import Observation

/// SwiftUI is the sole owner of the tab-bar behavior. A reveal stays latched
/// through the scroll interaction and deceleration; no timers or UIKit mutations.
@Observable
final class TabScrollRevealState {
    private(set) var isRevealed = false
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var latestOwner: UUID?
    @ObservationIgnored private var origin: CGFloat = 0
    @ObservationIgnored private var changedThisGesture = false
    static let threshold: CGFloat = 72

    func begin(owner: UUID, offset: CGFloat) {
        guard self.owner != owner else { return }
        self.owner = owner
        latestOwner = owner
        // Rearm before scrolling starts, so UIKit can observe the whole next
        // gesture. Restoring onScrollDown does not itself request minimization.
        isRevealed = false
        origin = offset
        changedThisGesture = false
    }

    func moved(owner: UUID, offset: CGFloat) {
        guard self.owner == owner, !changedThisGesture, offset.isFinite else { return }
        origin = max(origin, offset)
        guard origin - offset >= Self.threshold else { return }
        isRevealed = true
        changedThisGesture = true
    }

    func end(owner: UUID) {
        if self.owner == owner { self.owner = nil }
    }

    func settled(owner: UUID) {
        guard self.owner == nil, latestOwner == owner else { return }
        isRevealed = false
    }

    func reset() {
        owner = nil
        latestOwner = nil
        isRevealed = false
    }
}

private struct TabScrollRevealKey: EnvironmentKey {
    static let defaultValue: TabScrollRevealState? = nil
}

extension EnvironmentValues {
    var tabScrollReveal: TabScrollRevealState? {
        get { self[TabScrollRevealKey.self] }
        set { self[TabScrollRevealKey.self] = newValue }
    }
}
