import Foundation
import Observation

/// Observes `@Observable` state for imperative clients such as CarPlay and
/// playback projections. Registration is synchronous; delivery happens on the
/// next main-actor turn so the observer reads committed values.
///
/// Changes in one turn coalesce. Re-arm before invoking the callback so
/// mutations made by the callback are observed too. Release or cancel the
/// token to stop delivery.
@MainActor
final class ObservationToken {
    private var isCancelled = false

    fileprivate init() {}

    func cancel() {
        isCancelled = true
    }

    fileprivate var isActive: Bool { !isCancelled }
}

/// Calls `onChange` after coalesced changes to any `@Observable` property read
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
            armObservation(token: token, track: track, onChange: onChange)
            onChange()
        }
    }
}
