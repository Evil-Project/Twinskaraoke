import SwiftUI
import Observation

/// A short upward scroll reveals the tab bar. A reveal stays latched through
/// scrolling and its reveal animation; no timers.
///
/// Who actually performs the reveal is `TabRevealStrategy`'s business. With no
/// driver installed this publishes `isRevealed` and SwiftUI declares `.never`
/// for the length of the reveal — the shipping path. With a driver installed
/// `isRevealed` is deliberately left alone, because publishing it is a SwiftUI
/// update pass that can re-apply the declared behaviour and undo the reveal.
@Observable
final class TabScrollRevealState {
    /// The published reveal. Stays `false` on the UIKit-driven paths.
    private(set) var isRevealed = false
    /// The reveal as this object knows it, whoever is performing it.
    @ObservationIgnored private(set) var revealed = false
    @ObservationIgnored var handsBackOnIdle = true
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var latestOwner: UUID?
    @ObservationIgnored private var origin: CGFloat = 0
    @ObservationIgnored private var changedThisGesture = false
    @ObservationIgnored private var animationInFlight = false
    @ObservationIgnored private var handBackRequested = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let animate: (Animation?, () -> Void, @escaping () -> Void) -> Void
    @ObservationIgnored private var driver: Driver?
    @ObservationIgnored private var driverOwner: UUID?
    static let threshold: CGFloat = 72

    /// `(revealed, reduceMotion, completion)`. The completion reports when the
    /// transition it started has finished, so a hand-back cannot truncate it.
    typealias Driver = (Bool, Bool, @escaping () -> Void) -> Void

    init(animate: @escaping (Animation?, () -> Void, @escaping () -> Void) -> Void = { animation, changes, completion in
        withAnimation(animation, completionCriteria: .removed, changes, completion: completion)
    }) {
        self.animate = animate
    }

    func installDriver(owner: UUID, _ driver: @escaping Driver) {
        driverOwner = owner
        self.driver = driver
    }

    func removeDriver(owner: UUID) {
        guard driverOwner == owner else { return }
        driverOwner = nil
        driver = nil
        reset()
    }

    func begin(owner: UUID, offset: CGFloat) {
        guard self.owner != owner else { return }
        self.owner = owner
        latestOwner = owner
        // Rearm before scrolling starts, so UIKit can observe the whole next
        // gesture. Restoring onScrollDown does not itself request minimization.
        if !animationInFlight, revealed { apply(false, reduceMotion: true) {} }
        origin = offset
        changedThisGesture = false
    }

    func moved(owner: UUID, offset: CGFloat, reduceMotion: Bool = false) {
        guard self.owner == owner, !changedThisGesture, offset.isFinite else { return }
        origin = max(origin, offset)
        guard origin - offset >= Self.threshold else { return }
        changedThisGesture = true
        guard !revealed else { return }
        generation += 1
        let token = generation
        animationInFlight = true
        handBackRequested = false
        apply(true, reduceMotion: reduceMotion) { [weak self] in
            guard let self, generation == token else { return }
            animationInFlight = false
            finishHandBackIfReady()
        }
    }

    func end(owner: UUID) {
        if self.owner == owner { self.owner = nil }
    }

    func settled(owner: UUID) {
        guard handsBackOnIdle, self.owner == nil, latestOwner == owner else { return }
        handBackRequested = true
        finishHandBackIfReady()
    }

    private func finishHandBackIfReady() {
        guard handBackRequested, owner == nil, !animationInFlight else { return }
        handBackRequested = false
        apply(false, reduceMotion: true) {}
    }

    /// Changing policy back does not request a second visual transition, which
    /// is why the hand-back always passes `reduceMotion: true`.
    private func apply(_ next: Bool, reduceMotion: Bool, completion: @escaping () -> Void) {
        revealed = next
        if let driver {
            driver(next, reduceMotion, completion)
            return
        }
        guard next else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { isRevealed = false }
            completion()
            return
        }
        animate(reduceMotion ? nil : .smooth(duration: 0.35), { isRevealed = true }, completion)
    }

    func reset() {
        owner = nil
        latestOwner = nil
        generation += 1
        animationInFlight = false
        handBackRequested = false
        revealed = false
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
