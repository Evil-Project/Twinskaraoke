import Foundation
import Observation

/// A deadline owned by playback, independent of player visibility.
@MainActor
@Observable
final class SleepTimer {
    private(set) var deadline: Date?
    /// Stop when the song playing now ends, instead of at a time — Apple
    /// Music's "When Current Song Ends". Playback asks `consumeEndOfSong()`
    /// when a song finishes by itself.
    private(set) var endsWithCurrentSong = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let onExpiry: () -> Void

    init(onExpiry: @escaping () -> Void) {
        self.onExpiry = onExpiry
    }

    var isActive: Bool {
        deadline != nil || endsWithCurrentSong
    }

    func startEndOfSong() {
        cancel()
        endsWithCurrentSong = true
    }

    /// Whether a song that just ended should stop playback here. Disarms the
    /// timer when it does, so the stop happens once.
    func consumeEndOfSong() -> Bool {
        guard endsWithCurrentSong else { return false }
        endsWithCurrentSong = false
        return true
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
        endsWithCurrentSong = false
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
