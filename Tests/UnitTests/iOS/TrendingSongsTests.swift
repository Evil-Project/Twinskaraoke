import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Trending songs")
struct TrendingSongsTests {
    /// Shaped like a `/api/explore/trendings` response the week after a stream,
    /// when the newly sung songs still carry temporary audio.
    private static let responseAfterStream = Data("""
        [
          {"id": "dragula", "title": "Dragula", "coverArtists": ["Evil"],
           "originalArtists": ["Rob Zombie"], "duration": 222, "playCount": 7728},
          {"id": "temp-1", "title": "Temporary Stream Audio", "coverArtists": ["Evil"],
           "originalArtists": [], "duration": 180, "playCount": 1500},
          {"id": "how-to-pretend", "title": "How To Pretend", "coverArtists": ["Neuro", "Evil"],
           "originalArtists": ["Lucy Loone"], "duration": 196, "playCount": 1830},
          {"id": "temp-2", "title": "Thing (Temporary Stream Audio)", "coverArtists": ["Evil"],
           "originalArtists": [], "duration": 201, "playCount": 1239},
          {"id": "five-nights", "title": "Five Nights at Freddy's", "coverArtists": ["Evil"],
           "originalArtists": ["The Living Tombstone"], "duration": 238, "playCount": 1410}
        ]
        """.utf8)

    private func songs() throws -> [Song] {
        try JSONDecoder().decode([Song].self, from: Self.responseAfterStream)
    }

    private func query(days: Int, take: Int?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: KaraokeAPIClient.trendingQueryItems(days: days, take: take).map {
            ($0.name, $0.value ?? "")
        })
    }

    @Test("Stream placeholders are left out of the trending chart, in the server's order")
    func streamPlaceholdersAreLeftOut() throws {
        let chart = KaraokeAPIClient.trendingChart(try songs(), take: 20)

        #expect(chart.map(\.id) == ["dragula", "how-to-pretend", "five-nights"])
    }

    @Test("The chart stops at the requested number of songs after placeholders are dropped")
    func chartStopsAtTake() throws {
        let chart = KaraokeAPIClient.trendingChart(try songs(), take: 2)

        #expect(chart.map(\.id) == ["dragula", "how-to-pretend"])
    }

    @Test("Spare rows are requested so the chart stays full, up to the server's limit of 100")
    func spareRowsAreRequested() {
        #expect(query(days: 7, take: 20) == ["days": "7", "take": "40"])
        #expect(query(days: 7, take: 90) == ["days": "7", "take": "100"])
        // Without `take` the server already returns its maximum.
        #expect(query(days: 30, take: nil) == ["days": "30"])
    }

    private func real(_ id: String) -> Song {
        UITestFixtures.song(id: id, title: "Song \(id)", artist: "Evil")
    }

    private func placeholder(_ id: String) -> Song {
        UITestFixtures.song(id: id, title: "Temporary Stream Audio", artist: "Evil")
    }

    @Test("Asks again for the full list when placeholders leave the chart short")
    func asksAgainWhenPlaceholdersLeaveTheChartShort() {
        // `take: 2` asks for 22 songs; here 21 of them are placeholders.
        let mostlyPlaceholders = [real("a")] + (1...21).map { placeholder("p\($0)") }
        let onlyPlaceholders = (1...22).map { placeholder("p\($0)") }

        #expect(KaraokeAPIClient.needsMoreTrendingSongs(mostlyPlaceholders, take: 2))
        #expect(KaraokeAPIClient.needsMoreTrendingSongs(onlyPlaceholders, take: 2))
    }

    @Test("Doesn't ask again when the chart is full or the server has no more")
    func doesNotAskAgainWithoutCause() {
        let enough = [real("a"), real("b")] + (1...20).map { placeholder("p\($0)") }
        // Fewer songs than requested: the server has no more to give.
        let everythingTheServerHas = [real("a"), placeholder("p")]
        // `take: 90` already asks for the maximum of 100.
        let maximum = (1...100).map { placeholder("p\($0)") }

        #expect(!KaraokeAPIClient.needsMoreTrendingSongs(enough, take: 2))
        #expect(!KaraokeAPIClient.needsMoreTrendingSongs(everythingTheServerHas, take: 2))
        #expect(!KaraokeAPIClient.needsMoreTrendingSongs(maximum, take: 90))
        #expect(!KaraokeAPIClient.needsMoreTrendingSongs([placeholder("p")], take: nil))
    }

    /// `take: 2` asks for 22 songs; this window has one real song in them.
    private var shortWindow: [Song] {
        [real("a")] + (1...21).map { placeholder("p\($0)") }
    }

    @Test("A short chart is filled from a second request without take")
    func secondRequestFillsTheChart() async throws {
        let log = TrendingRequestLog()
        let fullList = shortWindow + [real("b"), real("c")]
        let chart = try await KaraokeAPIClient.trendingSongs(days: 7, take: 2) { items in
            await log.record(items) == 1 ? shortWindow : fullList
        }

        #expect(await log.takes == ["22", nil])
        #expect(chart.map(\.id) == ["a", "b"])
    }

    @Test("A failed second request keeps the songs from the first")
    func failedSecondRequestKeepsTheFirstChart() async throws {
        let log = TrendingRequestLog()
        let chart = try await KaraokeAPIClient.trendingSongs(days: 7, take: 2) { items in
            if await log.record(items) > 1 { throw URLError(.timedOut) }
            return shortWindow
        }

        #expect(chart.map(\.id) == ["a"])
    }

    @Test("A cancelled second request still ends the call")
    func cancelledSecondRequestThrows() async {
        let log = TrendingRequestLog()
        let window = shortWindow
        let task = Task {
            try await KaraokeAPIClient.trendingSongs(days: 7, take: 2) { items in
                if await log.record(items) > 1 {
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw URLError(.cancelled)
                }
                return window
            }
        }

        await #expect(throws: URLError.self) { try await task.value }
    }

    @Test("Out-of-range take values neither overflow nor trap")
    func outOfRangeTakeIsSafe() throws {
        #expect(query(days: 7, take: .max) == ["days": "7", "take": "100"])
        #expect(!KaraokeAPIClient.needsMoreTrendingSongs([real("a")], take: .max))
        #expect(KaraokeAPIClient.trendingChart(try songs(), take: -1).isEmpty)
    }
}

/// The `take` of each trending request a test's stand-in network receives.
private actor TrendingRequestLog {
    private(set) var takes: [String?] = []

    /// Records the request and returns how many there have been.
    func record(_ items: [URLQueryItem]) -> Int {
        takes.append(items.first { $0.name == "take" }?.value)
        return takes.count
    }
}
