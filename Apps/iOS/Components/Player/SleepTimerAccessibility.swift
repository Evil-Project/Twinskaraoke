import Foundation

/// What VoiceOver reads as the value of the sleep timer status in the player.
///
/// The status is labelled "Sleep timer remaining", so with a deadline the
/// value is the time left as a spelled-out duration ("14 minutes, 30
/// seconds"). The formatter does the wording per locale, so nothing is
/// concatenated and no catalog key is needed.
enum SleepTimerAccessibility {
    static func value(deadline: Date?, now: Date, locale: Locale) -> String {
        guard let deadline else { return String(localized: "End of Song") }
        // Whole seconds, rounded up, so a fresh 15-minute timer reads
        // "15 minutes" rather than "14 minutes, 59 seconds".
        let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2)
                .locale(locale)
        )
    }
}
