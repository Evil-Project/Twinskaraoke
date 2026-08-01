import AVFoundation
import Combine
import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

@MainActor
@Suite("Watch player observation lifetime")
struct WatchPlayerObservationLifetimeTests {
    @Test("Removing the lifetime cancels subscriptions and unregisters every observer")
    func removeAllFullyTearsDownPlayerObservations() {
        let lifetime = PlayerObservationLifetime()
        let cancellationCount = LockedWatchCounter()
        lifetime.store(AnyCancellable {
            cancellationCount.increment()
        })

        let player = AVPlayer()
        let timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { _ in }
        lifetime.replacePeriodicTimeObserver(timeObserver, on: player)

        let center = NotificationCenter()
        let notificationCount = LockedWatchCounter()
        let name = Notification.Name("WatchPlayerObservationLifetimeTests.ended")
        let endObserver = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            notificationCount.increment()
        }
        lifetime.replacePlaybackEndedObserver(endObserver, center: center)

        #expect(lifetime.subscriptionCount == 1)
        #expect(lifetime.hasPeriodicTimeObserver)
        #expect(lifetime.hasPlaybackEndedObserver)

        lifetime.removeAll()
        center.post(name: name, object: nil)

        #expect(lifetime.isEmpty)
        #expect(cancellationCount.value == 1)
        #expect(notificationCount.value == 0)

        lifetime.removeAll()
        #expect(cancellationCount.value == 1)
    }
}

private nonisolated final class LockedWatchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
