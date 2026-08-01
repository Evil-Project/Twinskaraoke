import Foundation

nonisolated struct PredownloadLifecycleState: Sendable {
    enum Phase: Equatable, Sendable {
        case running
        case validating
        case cancelled
        case finished
    }

    private(set) var phase: Phase = .running

    mutating func beginValidation() -> Bool {
        guard phase == .running else { return false }
        phase = .validating
        return true
    }

    mutating func cancel() -> Bool {
        guard phase == .running || phase == .validating else { return false }
        phase = .cancelled
        return true
    }

    mutating func finishWithoutValidation() -> Bool {
        guard phase == .running else { return false }
        phase = .finished
        return true
    }

    mutating func finishValidation() -> Bool {
        guard phase == .validating else { return false }
        phase = .finished
        return true
    }
}
