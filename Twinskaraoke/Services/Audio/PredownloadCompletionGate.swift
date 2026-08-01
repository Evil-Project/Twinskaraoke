import Foundation

/// Atomically transfers ownership of a transition predownload completion.
/// URLSession completion and explicit cancellation can race on different threads,
/// but only one path may resume the awaiting continuation.
nonisolated final class PredownloadCompletionGate: @unchecked Sendable {
    typealias Completion = @MainActor @Sendable () -> Void

    private let lock = NSLock()
    private var completion: Completion?

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func take() -> Completion? {
        lock.lock()
        defer { lock.unlock() }
        let claimedCompletion = completion
        completion = nil
        return claimedCompletion
    }
}
