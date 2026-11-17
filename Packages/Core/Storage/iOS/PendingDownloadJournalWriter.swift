import Foundation
import UIKit

/// Writes `DownloadManager`'s pending-download journal: every queued
/// download, full `Song` included, that a relaunch uses to adopt its
/// background transfers.
///
/// Adding songs writes at once (`writeNow()`): a transfer may start only once
/// its token is on disk, so the caller needs the result. Removing finished
/// songs used to rewrite the whole journal for each one, which made
/// "download all" quadratic on the main actor. Those removals go through
/// `scheduleWrite()` and coalesce into one write per `delay`. An entry that
/// outlives its download on disk is harmless: restoration skips songs that
/// are already downloaded. The scheduled write is flushed early when the app
/// leaves the foreground or terminates, and by `flush()`, which a background
/// wake calls before it reports its events handled.
@MainActor
final class PendingDownloadJournalWriter {
    typealias Write = @Sendable ([PendingDownload]) throws -> Void

    /// The journal to write, or nil while it hasn't been read from disk yet:
    /// writing then would drop the entries of a previous launch.
    var entries: () -> [PendingDownload]? = { nil }

    private let delay: Duration
    private let write: Write
    private let notificationCenter: NotificationCenter
    /// Serial, so writes land in the order their snapshots were taken.
    private let queue = DispatchQueue(label: "PendingDownloadJournalWriter", qos: .utility)
    private var scheduledWrite: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    convenience init(url: URL, delay: Duration = .seconds(1), notificationCenter: NotificationCenter = .default) {
        self.init(delay: delay, notificationCenter: notificationCenter) { entries in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        }
    }

    init(delay: Duration, notificationCenter: NotificationCenter, write: @escaping Write) {
        self.delay = delay
        self.write = write
        self.notificationCenter = notificationCenter
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Safe: `queue: .main` runs this block on the main queue, and
                // UIApplication posts these notifications on the main thread,
                // so the block runs synchronously before the app suspends.
                MainActor.assumeIsolated { self?.flush() }
            })
        }
    }

    isolated deinit {
        scheduledWrite?.cancel()
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    /// Writes the journal and returns whether it is on disk. False when it
    /// hasn't been loaded yet or the write failed.
    @discardableResult
    func writeNow() -> Bool {
        scheduledWrite?.cancel()
        scheduledWrite = nil
        guard let entries = entries() else { return false }
        let write = write
        // Synchronous: the caller needs the result, and the serial queue
        // orders this write behind any scheduled one still in flight.
        return queue.sync {
            do {
                try write(entries)
                return true
            } catch {
                DebugLogger.log("Pending download journal write failed: \(error)", category: .cache)
                return false
            }
        }
    }

    /// Writes the journal within `delay`, together with any other change
    /// scheduled before then.
    func scheduleWrite() {
        guard scheduledWrite == nil else { return }
        scheduledWrite = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.performScheduledWrite()
        }
    }

    /// Writes a scheduled change now and returns once every write so far is
    /// on disk.
    func flush() {
        if scheduledWrite != nil {
            writeNow()
        } else {
            queue.sync {}
        }
    }

    private func performScheduledWrite() {
        scheduledWrite = nil
        guard let entries = entries() else { return }
        let write = write
        queue.async {
            do {
                try write(entries)
            } catch {
                DebugLogger.log("Pending download journal write failed: \(error)", category: .cache)
            }
        }
    }
}
