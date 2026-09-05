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
