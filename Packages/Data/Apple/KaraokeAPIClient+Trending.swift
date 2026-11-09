import Foundation

/// `GET /api/explore/trendings`: the most played songs of the last 7 or 30
/// days, most played first.
nonisolated extension KaraokeAPIClient {
    /// Asks for 20 more songs than the caller shows, as `mostPlayedSongs`
    /// does, so the chart stays full once stream placeholders are dropped.
    /// The server caps `take` at 100.
    static func trendingQueryItems(days: Int, take: Int?) -> [URLQueryItem] {
        var queryItems = [URLQueryItem(name: "days", value: String(days))]
        if let take {
            queryItems.append(URLQueryItem(name: "take", value: String(min(take + 20, 100))))
        }
        return queryItems
    }

    /// The trending songs without stream placeholders, which have no real
    /// title yet, in the server's order and at most `take` of them.
    static func trendingChart(_ songs: [Song], take: Int?) -> [Song] {
        let chart = droppingStreamPlaceholders(songs)
        guard let take else { return chart }
        return Array(chart.prefix(take))
    }
}
