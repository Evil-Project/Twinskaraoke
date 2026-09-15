import SwiftUI
import Observation

/// SwiftUI is the sole owner of the tab-bar behavior. A reveal stays latched
/// through scrolling and its reveal animation; no timers or UIKit mutations.
@Observable
final class TabScrollRevealState {
    private(set) var isRevealed = false
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var latestOwner: UUID?
    @ObservationIgnored private var origin: CGFloat = 0
    @ObservationIgnored private var changedThisGesture = false
    @ObservationIgnored private var animationInFlight = false
    @ObservationIgnored private var handBackRequested = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let animate: (Animation?, () -> Void, @escaping () -> Void) -> Void
    static let threshold: CGFloat = 72

    init(animate: @escaping (Animation?, () -> Void, @escaping () -> Void) -> Void = { animation, changes, completion in
        withAnimation(animation, completionCriteria: .removed, changes, completion: completion)
    }) {
        self.animate = animate
    }

    func begin(owner: UUID, offset: CGFloat) {
        guard self.owner != owner else { return }
        self.owner = owner
        latestOwner = owner
        // Rearm before scrolling starts, so UIKit can observe the whole next
        // gesture. Restoring onScrollDown does not itself request minimization.
        if !animationInFlight { isRevealed = false }
        origin = offset
        changedThisGesture = false
    }

    func moved(owner: UUID, offset: CGFloat, reduceMotion: Bool = false) {
        guard self.owner == owner, !changedThisGesture, offset.isFinite else { return }
        origin = max(origin, offset)
        guard origin - offset >= Self.threshold else { return }
        changedThisGesture = true
        guard !isRevealed else { return }
        generation += 1
        let token = generation
        animationInFlight = true
        handBackRequested = false
        animate(reduceMotion ? nil : .smooth(duration: 0.35), {
            isRevealed = true
        }, { [weak self] in
            guard let self, generation == token else { return }
            animationInFlight = false
            finishHandBackIfReady()
        })
    }

    func end(owner: UUID) {
        if self.owner == owner { self.owner = nil }
    }

    func settled(owner: UUID) {
        guard self.owner == nil, latestOwner == owner else { return }
        handBackRequested = true
        finishHandBackIfReady()
    }

    private func finishHandBackIfReady() {
        guard handBackRequested, owner == nil, !animationInFlight else { return }
        handBackRequested = false
        // Changing policy does not request a second visual transition.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { isRevealed = false }
    }

    func reset() {
        owner = nil
        latestOwner = nil
        generation += 1
        animationInFlight = false
        handBackRequested = false
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
