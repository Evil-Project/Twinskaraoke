import AVFoundation
import Combine
import Foundation

// AudioManager is main-actor isolated, but its deinit is synchronous and
// nonisolated. Detaching tokens under a lock keeps both teardown paths safe.
nonisolated final class PlayerObservationLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var subscriptions = Set<AnyCancellable>()
    private var periodicTimeObserver: (player: AVPlayer, token: Any)?
    private var playbackEndedObserver: (center: NotificationCenter, token: NSObjectProtocol)?

    var subscriptionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return subscriptions.count
    }

    var hasPeriodicTimeObserver: Bool {
        lock.lock()
        defer { lock.unlock() }
        return periodicTimeObserver != nil
    }

    var hasPlaybackEndedObserver: Bool {
        lock.lock()
        defer { lock.unlock() }
        return playbackEndedObserver != nil
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return subscriptions.isEmpty
            && periodicTimeObserver == nil
            && playbackEndedObserver == nil
    }

    func store(_ subscription: AnyCancellable) {
        lock.lock()
        subscriptions.insert(subscription)
        lock.unlock()
    }

    func replacePeriodicTimeObserver(_ token: Any, on player: AVPlayer) {
        lock.lock()
        let previous = periodicTimeObserver
        periodicTimeObserver = (player, token)
        lock.unlock()
        if let previous {
            previous.player.removeTimeObserver(previous.token)
        }
    }

    func replacePlaybackEndedObserver(
        _ token: NSObjectProtocol,
        center: NotificationCenter = .default
    ) {
        lock.lock()
        let previous = playbackEndedObserver
        playbackEndedObserver = (center, token)
        lock.unlock()
        if let previous {
            previous.center.removeObserver(previous.token)
        }
    }

    func removeAll() {
        lock.lock()
        let detachedSubscriptions = subscriptions
        let detachedPeriodicTimeObserver = periodicTimeObserver
        let detachedPlaybackEndedObserver = playbackEndedObserver
        subscriptions = []
        periodicTimeObserver = nil
        playbackEndedObserver = nil
        lock.unlock()

        detachedSubscriptions.forEach { $0.cancel() }
        if let detachedPeriodicTimeObserver {
            detachedPeriodicTimeObserver.player.removeTimeObserver(
                detachedPeriodicTimeObserver.token
            )
        }
        if let detachedPlaybackEndedObserver {
            detachedPlaybackEndedObserver.center.removeObserver(detachedPlaybackEndedObserver.token)
        }
    }

    deinit {
        removeAll()
    }
}
