import AVFoundation
import Foundation

@MainActor
final class WatchAudioSessionCoordinator {
    typealias Completion = @MainActor (Result<Void, Error>) -> Void
    typealias Activation = @MainActor (@escaping Completion) -> Void

    typealias Deactivation = @MainActor (@escaping @MainActor (Bool) -> Void) -> Void

    private let activate: Activation
    private let deactivate: Deactivation
    private var generation: UInt64 = 0
    private var activationInFlight = false
    private var deactivationInFlight = false
    private var releaseUnconfirmed = false
    private var pendingPlayback: Completion?
    private(set) var isActive = false

    init(
        activate: @escaping Activation = WatchAudioSessionCoordinator.activateSession,
        deactivate: @escaping Deactivation = WatchAudioSessionCoordinator.deactivateSession
    ) {
        self.activate = activate
        self.deactivate = deactivate
    }

    func request(_ completion: @escaping Completion) {
        if isActive {
            completion(.success(()))
            return
        }
        pendingPlayback = completion
        activateIfNeeded()
    }

    func cancelPendingPlayback() {
        pendingPlayback = nil
    }

    func invalidate() {
        generation &+= 1
        isActive = false
        cancelPendingPlayback()
    }

    func relinquish() {
        let wasActive = isActive
        invalidate()
        if !activationInFlight, wasActive || releaseUnconfirmed { releaseSession() }
    }

    private func releaseSession() {
        guard !deactivationInFlight else { return }
        deactivationInFlight = true
        deactivate { [weak self] released in
            guard let self else { return }
            self.deactivationInFlight = false
            self.releaseUnconfirmed = !released
            self.activateIfNeeded()
        }
    }

    private func activateIfNeeded() {
        guard pendingPlayback != nil, !activationInFlight, !deactivationInFlight else { return }
        activationInFlight = true
        let generation = generation
        activate { [weak self] result in
            guard let self else { return }
            self.activationInFlight = false
            guard self.generation == generation else {
                // Complete any required release before another request can activate.
                if case .success = result { self.releaseSession() }
                else { self.activateIfNeeded() }
                return
            }
            let playback = self.pendingPlayback
            self.pendingPlayback = nil
            switch result {
            case .success:
                self.releaseUnconfirmed = false
                self.isActive = true
            case let .failure(error):
                DebugLogger.log("Watch audio session activation failed: \(error)", category: .playback)
            }
            playback?(result)
        }
    }

    private static func activateSession(_ completion: @escaping Completion) {
        Task.detached(priority: .userInitiated) {
            let result = await Self.bringUpSession()
            await completion(result)
        }
    }

    private static func deactivateSession(_ completion: @escaping @MainActor (Bool) -> Void) {
        Task.detached(priority: .userInitiated) {
            let released = Self.releaseAudioSession()
            await completion(released)
        }
    }

    private nonisolated static func releaseAudioSession() -> Bool {
        // AVAudioSession documents that isBusy still leaves the session inactive.
        for attempt in 0..<2 {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                return true
            } catch {
                let status = error as NSError
                if status.domain == NSOSStatusErrorDomain,
                   status.code == AVAudioSession.ErrorCode.isBusy.rawValue { return true }
                DebugLogger.log("Watch audio session deactivation attempt \(attempt + 1) failed: \(error)", category: .playback)
            }
        }
        return false
    }

    private nonisolated static func bringUpSession() async -> Result<Void, Error> {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            return await withCheckedContinuation { continuation in
                session.activate(options: []) { @Sendable success, error in
                    if let error {
                        continuation.resume(returning: .failure(error))
                    } else if success {
                        continuation.resume(returning: .success(()))
                    } else {
                        continuation.resume(returning: .failure(ActivationError.unsuccessful))
                    }
                }
            }
        } catch {
            return .failure(error)
        }
    }

    private enum ActivationError: Error {
        case unsuccessful
    }
}
