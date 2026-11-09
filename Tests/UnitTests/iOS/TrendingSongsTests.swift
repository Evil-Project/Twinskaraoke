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
}
