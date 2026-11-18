import Observation
import Testing

/// Observe real state transitions; a deadline reports missing events without polling windows.
@MainActor private final class SplashConditionWaiter {
    let condition: @MainActor () -> Bool
    var continuation: AsyncStream<Bool>.Continuation?

    init(condition: @escaping @MainActor () -> Bool, continuation: AsyncStream<Bool>.Continuation) {
        self.condition = condition
        self.continuation = continuation
    }

    func observe() {
        guard continuation != nil else { return }
        let ready = withObservationTracking { condition() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        if ready { continuation?.yield(true); continuation?.finish() }
    }
}

@MainActor func waitForSplashCondition(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    let (events, continuation) = AsyncStream<Bool>.makeStream()
    let waiter = SplashConditionWaiter(condition: condition, continuation: continuation)
    waiter.observe()
    let deadline = Task {
        do { try await Task.sleep(for: .seconds(15)) } catch { return }
        continuation.yield(false)
        continuation.finish()
    }
    defer { deadline.cancel(); waiter.continuation = nil; continuation.finish() }
    var iterator = events.makeAsyncIterator()
    let result = await iterator.next()
    try #require(result == true, "Timed out waiting for a splash state transition", sourceLocation: sourceLocation)
}
