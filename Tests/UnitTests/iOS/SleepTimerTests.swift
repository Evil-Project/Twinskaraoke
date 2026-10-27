import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Sleep timer")
struct SleepTimerTests {
    @Test func expiresOnceAndClearsDeadline() throws {
        var expirations = 0
        let timer = SleepTimer { expirations += 1 }
        timer.start(minutes: 15)
        let deadline = try #require(timer.deadline)
        timer.checkExpiry(now: deadline.addingTimeInterval(-1))
        #expect(expirations == 0)
        timer.checkExpiry(now: deadline)
        timer.checkExpiry(now: deadline.addingTimeInterval(1))
        #expect(expirations == 1)
        #expect(timer.deadline == nil)
    }

    @Test func cancellationPreventsExpiry() throws {
        var expired = false
        let timer = SleepTimer { expired = true }
        timer.start(minutes: 15)
        let deadline = try #require(timer.deadline)
        timer.cancel()
        timer.checkExpiry(now: deadline)
        #expect(!expired)
        #expect(timer.deadline == nil)
    }

    @Test func endOfSongStopsOnceWithoutADeadline() {
        var expired = false
        let timer = SleepTimer { expired = true }
        #expect(!timer.consumeEndOfSong())

        timer.startEndOfSong()
        #expect(timer.isActive)
        #expect(timer.deadline == nil)
        #expect(timer.consumeEndOfSong())
        // Stops at one song end, not every one after it.
        #expect(!timer.consumeEndOfSong())
        #expect(!timer.isActive)
        // The time-based expiry path is not involved.
        #expect(!expired)
    }

    @Test func endOfSongAndDurationsReplaceEachOther() throws {
        let timer = SleepTimer {}
        timer.startEndOfSong()
        timer.start(minutes: 30)
        #expect(!timer.endsWithCurrentSong)
        _ = try #require(timer.deadline)

        timer.startEndOfSong()
        #expect(timer.deadline == nil)
        #expect(timer.endsWithCurrentSong)

        timer.cancel()
        #expect(!timer.isActive)
        #expect(!timer.consumeEndOfSong())
    }

    @Test func replacingTimerDiscardsOldDeadline() throws {
        var expired = false
        let timer = SleepTimer { expired = true }
        timer.start(minutes: 15)
        let oldDeadline = try #require(timer.deadline)
        timer.start(minutes: 60)
        timer.checkExpiry(now: oldDeadline)
        #expect(!expired)
        #expect(try #require(timer.deadline) > oldDeadline)
        timer.cancel()
    }
}
