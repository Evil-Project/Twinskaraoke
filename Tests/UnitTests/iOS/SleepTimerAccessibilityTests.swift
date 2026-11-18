import Foundation
import Testing
@testable import Twinskaraoke

/// The player's sleep timer status is read as "Sleep timer remaining"; its
/// value must say how long is left, not be empty.
@Suite("Sleep timer accessibility value")
struct SleepTimerAccessibilityTests {
    private let now = Date(timeIntervalSinceReferenceDate: 0)
    private let locale = Locale(identifier: "en_US")

    @Test func aDeadlineReadsAsTheTimeRemaining() {
        let value = SleepTimerAccessibility.value(deadline: now.addingTimeInterval(14 * 60 + 30), now: now, locale: locale)
        #expect(value == "14 minutes, 30 seconds")
    }

    @Test func longTimersReadHoursAndMinutes() {
        let value = SleepTimerAccessibility.value(deadline: now.addingTimeInterval(3660), now: now, locale: locale)
        #expect(value == "1 hour, 1 minute")
    }

    @Test func aPassedDeadlineReadsAsNothingLeft() {
        let value = SleepTimerAccessibility.value(deadline: now.addingTimeInterval(-5), now: now, locale: locale)
        #expect(value == "0 seconds")
    }

    /// The label comes from the catalog in the host's language, so compare
    /// with the same lookup rather than with the English source.
    @Test func endOfSongKeepsItsValue() {
        #expect(SleepTimerAccessibility.value(deadline: nil, now: now, locale: locale) == String(localized: "End of Song"))
    }
}
