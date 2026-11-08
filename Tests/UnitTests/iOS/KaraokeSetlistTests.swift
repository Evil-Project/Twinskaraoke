import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Karaoke setlists")
struct KaraokeSetlistTests {
    private func decode(_ json: String) throws -> KaraokeSetlist {
        try JSONDecoder().decode(KaraokeSetlist.self, from: Data(json.utf8))
    }

    @Test("A setlist keeps its playlist fields, length and stream day")
    func decodesSetlist() throws {
        let setlist = try decode(#"""
            {"id":"e9bb","name":"Evil Halloween Karaoke - October 29, 2026 Setlist","songCount":15,
             "totalDuration":3191,"setListDate":"2026-10-29T00:00:00","isSetList":true,"playlistType":0,
             "songListDTOs":[{"id":"s1","title":"This Is Halloween","duration":201}]}
            """#)
        #expect(setlist.id == "e9bb")
        #expect(setlist.playlist.name == "Evil Halloween Karaoke - October 29, 2026 Setlist")
        #expect(setlist.playlist.songCount == 15)
        #expect(setlist.playlist.songListDTOs?.map(\.id) == ["s1"])
        #expect(setlist.totalDuration == 3191)
        #expect(setlist.streamDay == DateComponents(year: 2026, month: 10, day: 29))
    }

    @Test("The stream day ignores the time and its seven-digit fraction, and reads the same in every time zone")
    func readsOnlyTheDate() throws {
        let day = try #require(KaraokeSetlist.day(from: "2025-12-27T20:14:06.4719616"))
        #expect(day == DateComponents(year: 2025, month: 12, day: 27))
        // The extremes, 25 hours apart: a stored instant would fall on
        // different days in them.
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone))
            let date = try #require(calendar.date(from: day))
            #expect(calendar.component(.day, from: date) == 27, "\(zone)")
        }
        #expect(KaraokeSetlist.day(from: "not a date") == nil)
        #expect(KaraokeSetlist.day(from: "2026-13-40T00:00:00") == nil)
    }

    @Test("Missing values decode as absent, and a missing count comes from the songs")
    func toleratesMissingValues() throws {
        let setlist = try decode(#"""
            {"id":"a","name":"A","setListDate":null,
             "songListDTOs":[{"id":"s1","title":"One"},{"id":"s2","title":"Two"}]}
            """#)
        #expect(setlist.streamDay == nil)
        #expect(setlist.totalDuration == nil)
        #expect(setlist.playlist.songCount == 2)
    }

    @Test("Counting the songs keeps the rest of the playlist")
    func countFallbackKeepsPlaylistFields() throws {
        let setlist = try decode(#"{"id":"a","name":"A","isPersonal":true,"songListDTOs":[{"id":"s1","title":"One"}]}"#)
        #expect(setlist.playlist.songCount == 1)
        #expect(setlist.playlist.isPersonal)
    }

    @Test("Stats list the years newest first, once each")
    func decodesStats() throws {
        let stats = try JSONDecoder().decode(
            SetlistStats.self,
            from: Data(#"{"totalCount":109,"years":[2024,2026,2025,2023,2026]}"#.utf8)
        )
        #expect(stats == SetlistStats(totalCount: 109, years: [2026, 2025, 2024, 2023]))
        #expect(stats.years == [2026, 2025, 2024, 2023])
    }

    @Test("Stats that don't match fail to decode instead of reading as no years")
    func rejectsMalformedStats() {
        for json in [#"{}"#, #"{"totalCount":109}"#, #"{"totalCount":109,"years":["2026"]}"#] {
            #expect(throws: DecodingError.self, "\(json)") {
                try JSONDecoder().decode(SetlistStats.self, from: Data(json.utf8))
            }
        }
    }

    @Test("The setlist request asks for newest first, and filters by year and search only when they're set")
    func buildsRequest() throws {
        let filtered = try KaraokeAPIClient.setlistsRequest(
            startIndex: 25,
            pageSize: 25,
            year: 2024,
            search: "christmas",
            readToken: { nil }
        )
        let url = try #require(filtered.url)
        #expect(url.path == "/api/playlists")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(Set(items) == [
            URLQueryItem(name: "isSetlist", value: "True"),
            URLQueryItem(name: "startIndex", value: "25"),
            URLQueryItem(name: "pageSize", value: "25"),
            URLQueryItem(name: "sortDescending", value: "True"),
            URLQueryItem(name: "year", value: "2024"),
            URLQueryItem(name: "search", value: "christmas"),
        ])

        let all = try KaraokeAPIClient.setlistsRequest(startIndex: 0, pageSize: 25, year: nil, search: "", readToken: { nil })
        let names = (URLComponents(url: try #require(all.url), resolvingAgainstBaseURL: false)?.queryItems ?? []).map(\.name)
        #expect(Set(names) == ["isSetlist", "startIndex", "pageSize", "sortDescending"])
    }
}
