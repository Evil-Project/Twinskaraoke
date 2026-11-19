import Foundation

/// Reads the server's `date-span` values (.NET `TimeSpan` text such as
/// `00:01:12`, `00:00:09.5000000` or `1.02:03:04`).
nonisolated enum BandleTimeSpan {
    /// `TimeSpan.MaxValue` is 10675199 days; larger counts are malformed and
    /// would overflow `Int` below.
    private static let maxDays = 10_675_199

    static func duration(from text: String) -> Duration? {
        // Negative spans never describe time spent playing.
        guard !text.hasPrefix("-") else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var days = 0
        var hoursText = parts[0]
        if let dot = hoursText.firstIndex(of: ".") {
            guard let parsedDays = Int(hoursText[..<dot]) else { return nil }
            days = parsedDays
            hoursText = hoursText[hoursText.index(after: dot)...]
        }
        guard (0 ... maxDays).contains(days),
              let hours = Int(hoursText), (0 ..< 24).contains(hours),
              let minutes = Int(parts[1]), (0 ..< 60).contains(minutes),
              let second = secondsAndNanoseconds(parts[2])
        else { return nil }

        let wholeSeconds = ((days * 24 + hours) * 60 + minutes) * 60 + second.whole
        return .seconds(wholeSeconds) + .nanoseconds(second.nanoseconds)
    }

    /// `SS` or `SS.fffffff`, read as integers. Through `Double`, 100 ns
    /// ticks picked up binary error, so a sum of times meant to be whole
    /// seconds landed just below and read a second low once truncated.
    private static func secondsAndNanoseconds(_ text: Substring) -> (whole: Int, nanoseconds: Int)? {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2,
              pieces[0].allSatisfy(isDigit),
              let seconds = Int(pieces[0]), (0 ..< 60).contains(seconds)
        else { return nil }
        guard pieces.count == 2 else { return (seconds, 0) }

        // Digits past nanoseconds are dropped, never rounded up into the
        // next second.
        let fraction = pieces[1]
        guard !fraction.isEmpty, fraction.allSatisfy(isDigit) else { return nil }
        let digits = String(fraction.prefix(9)).padding(toLength: 9, withPad: "0", startingAt: 0)
        guard let nanoseconds = Int(digits) else { return nil }
        return (seconds, nanoseconds)
    }

    private static func isDigit(_ character: Character) -> Bool {
        ("0" ... "9").contains(character)
    }
}
