import Foundation
import Observation

/// A deadline owned by playback, independent of player visibility.
@MainActor
@Observable
final class SleepTimer {
    private(set) var deadline: Date?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let onExpiry: () -> Void

    init(onExpiry: @escaping () -> Void) {
        self.onExpiry = onExpiry
    }

    func start(minutes: Int) {
        guard minutes > 0 else { return }
        cancel()
        let duration = TimeInterval(minutes) * 60
        deadline = Date().addingTimeInterval(duration)
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            self?.expire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        deadline = nil
    }

    /// Reconcile after suspension as well as the scheduled background expiry.
    func checkExpiry(now: Date = .now) {
        guard let deadline, now >= deadline else { return }
        expire()
    }

    private func expire() {
        guard deadline != nil else { return }
        cancel()
        onExpiry()
    }

    deinit {
        task?.cancel()
    }
}
