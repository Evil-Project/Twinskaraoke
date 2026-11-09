import Foundation

/// `GET /api/explore/trendings`: the most played songs of the last 7 or 30
/// days, most played first.
nonisolated extension KaraokeAPIClient {
    /// Only `days` of 7 and 30 return data; the results are precomputed for
    /// those two windows. For an all-time chart use `mostPlayedSongs`.
    ///
    /// Stream placeholders are left out. If they leave the first response
    /// short of `take` songs and the server has more, it asks once more for
    /// the most it returns.
    ///
    /// `fetch` sends one request; tests pass a stand-in for the network.
    static func trendingSongs(
        days: Int = 7,
        take: Int? = nil,
        fetch: ([URLQueryItem]) async throws -> [Song] = KaraokeAPIClient.trendingResponse
    ) async throws -> [Song] {
        var songs = try await fetch(trendingQueryItems(days: days, take: take))
        if needsMoreTrendingSongs(songs, take: take) {
            do {
                // Without `take` the server returns its maximum, 100 songs.
                songs = try await fetch(trendingQueryItems(days: days, take: nil))
            } catch {
                // A failed second request keeps the first, shorter chart; a
                // cancelled one still ends the call.
                if Task.isCancelled { throw error }
            }
        }
        return trendingChart(songs, take: take)
    }

    /// Asks for 20 more songs than the caller shows, as `mostPlayedSongs`
    /// does, so the chart usually stays full once stream placeholders are
    /// dropped. The server caps `take` at 100.
    static func trendingQueryItems(days: Int, take: Int?) -> [URLQueryItem] {
        var queryItems = [URLQueryItem(name: "days", value: String(days))]
        if let take {
            queryItems.append(URLQueryItem(name: "take", value: String(trendingRequestSize(for: take))))
        }
        return queryItems
    }

    /// Whether placeholders left the first response short of `take` real
    /// songs while the server may have more: it sent every song asked for,
    /// and that was fewer than its maximum.
    static func needsMoreTrendingSongs(_ response: [Song], take: Int?) -> Bool {
        guard let take else { return false }
        let requested = trendingRequestSize(for: take)
        guard requested < 100, response.count >= requested else { return false }
        return response.count(where: { !isStreamPlaceholder($0) }) < take
    }

    /// The trending songs without stream placeholders, which have no real
    /// title yet, in the server's order and at most `take` of them.
    static func trendingChart(_ songs: [Song], take: Int?) -> [Song] {
        let chart = droppingStreamPlaceholders(songs)
        guard let take else { return chart }
        return Array(chart.prefix(max(take, 0)))
    }

    /// `take` and 20 spare songs, up to the server's 100. Compares before
    /// adding, so even `Int.max` can't overflow.
    private static func trendingRequestSize(for take: Int) -> Int {
        take >= 80 ? 100 : max(take, 0) + 20
    }

    static func trendingResponse(_ queryItems: [URLQueryItem]) async throws -> [Song] {
        let request = try request(path: "/api/explore/trendings", queryItems: queryItems)
        let data = try await data(for: request)
        return try JSONDecoder().decode([Song].self, from: data)
    }
}
