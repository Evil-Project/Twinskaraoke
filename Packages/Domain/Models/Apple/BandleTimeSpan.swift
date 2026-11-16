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
              let seconds = Double(parts[2]), seconds >= 0, seconds < 60
        else { return nil }

        let wholeSeconds = ((days * 24 + hours) * 60 + minutes) * 60
        return .seconds(wholeSeconds) + .seconds(seconds)
    }
}
