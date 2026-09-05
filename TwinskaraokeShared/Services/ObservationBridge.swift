import Foundation
import Observation

/// Re-arming bridge from `@Observable` back to imperative change callbacks.
///
/// `@Observable` has no publisher projection, so the `$property.sink` pipelines
/// this app used for cross-module wiring (CarPlay, the popup bar, the Shimeji
/// overlay) have no direct equivalent. `withObservationTracking` is the
/// replacement primitive, but it differs from `sink` in two ways that matter:
///
///   * it fires `onChange` **once** and then stops tracking, and
///   * it fires *before* the write lands, so reading inside `onChange` still
///     yields the old value.
///
/// This wrapper restores `sink` semantics — a callback after every change, for
/// as long as the token is held — by hopping to the next main-actor turn (so
/// the new value is visible) and then re-arming.
///
/// Cancel by releasing the token or calling `cancel()`; a cancelled token stops
/// re-arming, which is what keeps view models from observing past their own
/// lifetime.
@MainActor
final class ObservationToken {
    private var isCancelled = false

    fileprivate init() {}

    func cancel() {
        isCancelled = true
    }

    fileprivate var isActive: Bool { !isCancelled }

    deinit {
        // `isCancelled` is plain stored state on a MainActor type; the isolated
        // deinit lets us touch it without hopping. See the house pattern note
        // in AVEnginePlayback/AudioPlayerManager.
        isCancelled = true
    }
}

/// Calls `onChange` after every change to any `@Observable` property read
/// inside `track`, until the returned token is cancelled or released.
///
/// `track` must actually *read* the properties to observe — that read is what
/// registers them. Returning them is not required.
@MainActor
@discardableResult
func observeContinuously(
    _ track: @escaping @MainActor () -> Void,
    onChange: @escaping @MainActor () -> Void
) -> ObservationToken {
    let token = ObservationToken()
    armObservation(token: token, track: track, onChange: onChange)
    return token
}

@MainActor
private func armObservation(
    token: ObservationToken,
    track: @escaping @MainActor () -> Void,
    onChange: @escaping @MainActor () -> Void
) {
    guard token.isActive else { return }
    withObservationTracking {
        track()
    } onChange: { [weak token] in
        // onChange runs in the mutating context, before the value is written,
        // and is not main-actor isolated. Hop so observers see the new value.
        Task { @MainActor [weak token] in
            guard let token, token.isActive else { return }
            onChange()
            armObservation(token: token, track: track, onChange: onChange)
        }
    }
}
