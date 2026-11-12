import AVFoundation
import Foundation

@MainActor
final class WatchAudioSessionCoordinator {
    typealias Completion = @MainActor (Result<Void, Error>) -> Void
    typealias Activation = @MainActor (@escaping Completion) -> Void

    private let activate: Activation
    private var generation: UInt64 = 0
    private var activationInFlight = false
    private var pendingPlayback: Completion?
    private(set) var isActive = false

    init(activate: @escaping Activation = WatchAudioSessionCoordinator.activateSession) {
        self.activate = activate
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

    private func activateIfNeeded() {
        guard pendingPlayback != nil, !activationInFlight else { return }
        activationInFlight = true
        let generation = generation
        activate { [weak self] result in
            guard let self else { return }
            self.activationInFlight = false
            guard self.generation == generation else {
                // Let the old system call settle before issuing another one.
                self.activateIfNeeded()
                return
            }
            let playback = self.pendingPlayback
            self.pendingPlayback = nil
            switch result {
            case .success:
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
