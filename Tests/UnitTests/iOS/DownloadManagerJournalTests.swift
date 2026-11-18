import Foundation
import Synchronization
import Testing
import UIKit
@testable import Twinskaraoke

@Suite("Pending download journal")
@MainActor
struct DownloadManagerJournalTests {
    @Test("Finishing many downloads rewrites the pending journal once, not once per song")
    func finishedDownloadsCoalesceJournalWrites() async throws {
        let writes = Mutex<[[PendingDownload]]>([])
        let (written, continuation) = AsyncStream.makeStream(of: Void.self)
        let writer = PendingDownloadJournalWriter(delay: .milliseconds(50), notificationCenter: NotificationCenter()) { entries in
            writes.withLock { $0.append(entries) }
            continuation.yield()
        }
        var pending = Dictionary(uniqueKeysWithValues: journalFixtures(100).map { ($0.song.id, $0) })
        writer.entries = { Array(pending.values) }
        #expect(writer.writeNow())

        let finished = pending.keys.sorted().dropLast(3)
        for songID in finished {
            pending.removeValue(forKey: songID)
            writer.scheduleWrite()
        }
        var iterator = written.makeAsyncIterator()
        _ = await iterator.next()
        _ = await iterator.next()
        writer.flush()

        let recorded = writes.withLock { $0 }
        #expect(recorded.count == 2)
        #expect(Set(try #require(recorded.last).map(\.token)) == Set(pending.values.map(\.token)))
    }

    @Test("Leaving the foreground writes a scheduled journal change before suspension")
    func backgroundingFlushesScheduledJournalWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pending-downloads.json")
        let center = NotificationCenter()
        // Long enough that only the notification can have written the change.
        let writer = PendingDownloadJournalWriter(url: url, delay: .seconds(60), notificationCenter: center)
        var pending = Dictionary(uniqueKeysWithValues: journalFixtures(20).map { ($0.song.id, $0) })
        writer.entries = { Array(pending.values) }
        #expect(writer.writeNow())

        for songID in pending.keys.sorted().prefix(15) {
            pending.removeValue(forKey: songID)
            writer.scheduleWrite()
        }
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        let journal = try JSONDecoder().decode([PendingDownload].self, from: Data(contentsOf: url))
        #expect(journal.count == 5)
        #expect(Set(journal.map(\.token)) == Set(pending.values.map(\.token)))
    }

    @Test("The journal is not written before it has been read from disk")
    func unloadedJournalIsNotWritten() {
        let writes = Mutex(0)
        let writer = PendingDownloadJournalWriter(delay: .zero, notificationCenter: NotificationCenter()) { _ in
            writes.withLock { $0 += 1 }
        }
        writer.entries = { nil }
        #expect(!writer.writeNow())
        writer.scheduleWrite()
        writer.flush()
        #expect(writes.withLock { $0 } == 0)
    }

    private func journalFixtures(_ count: Int) -> [PendingDownload] {
        (0 ..< count).map { index in
            PendingDownload(
                song: Song(
                    id: "journal-\(index)",
                    title: "Song \(index)",
                    duration: 180,
                    absolutePath: "/audio/journal-\(index).mp3",
                    cloudflareID: nil,
                    coverArt: nil,
                    originalArtists: nil,
                    coverArtists: nil,
                    userUploaded: false
                ),
                token: UUID()
            )
        }
    }
}
