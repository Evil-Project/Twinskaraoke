import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

@Suite("Radio now playing")
struct RadioNowPlayingTests {
    /// Shape taken from the live station endpoint, which is snake_cased while
    /// the Swift properties are not.
    private let payload = Data("""
    {
      "station": {
        "name": "Twinskaraoke Radio",
        "description": "Neuro 21",
        "listen_url": "https://radio.twinskaraoke.com/listen/neuro_21/radio.mp3"
      },
      "listeners": { "total": 42, "unique": 24 },
      "now_playing": {
        "song": {
          "id": "hash-abc",
          "art": "https://example.invalid/art.jpg",
          "text": "Hero - Mili",
          "artist": "Mili",
          "title": "Hero",
          "custom_fields": { "songId": "catalog-123" }
        }
      },
      "playing_next": {
        "song": { "id": "hash-def", "art": null, "text": "Next - Someone",
                  "artist": "Someone", "title": "Next", "custom_fields": null }
      },
      "song_history": [
        { "song": { "id": "hash-ghi", "art": null, "text": "Past - Nobody",
                    "artist": "Nobody", "title": "Past", "custom_fields": null } }
      ]
    }
    """.utf8)

    @Test("Station metadata decodes from the live wire format")
    func decodesWireFormat() throws {
        let decoded = try JSONDecoder().decode(RadioNowPlaying.self, from: payload)

        #expect(decoded.station.name == "Twinskaraoke Radio")
        #expect(decoded.station.listenUrl.hasSuffix("radio.mp3"))
        #expect(decoded.listeners?.total == 42)
        #expect(decoded.nowPlaying?.song.title == "Hero")
        #expect(decoded.playingNext?.song.title == "Next")
        #expect(decoded.songHistory?.count == 1)
    }

    /// The station's own ID is a rotating hash; the catalog ID in
    /// `custom_fields` is what actually identifies the song.
    @Test("A track with a catalog ID resolves to that ID, not the station hash")
    func prefersCatalogIdentifier() throws {
        let decoded = try JSONDecoder().decode(RadioNowPlaying.self, from: payload)
        let info = try #require(decoded.nowPlaying?.song)

        #expect(info.resolvedSongID == "catalog-123")
        #expect(info.toSong(stationID: "neuro_21").id == "catalog-123")
    }

    @Test("A track with no catalog ID falls back to a station-scoped ID")
    func fallsBackToStationIdentifier() throws {
        let decoded = try JSONDecoder().decode(RadioNowPlaying.self, from: payload)
        let info = try #require(decoded.playingNext?.song)

        #expect(info.resolvedSongID == nil)
        #expect(info.toSong(stationID: "neuro_21").id == "radio:neuro_21")
    }

    /// Optional sections are genuinely absent between tracks, not null.
    @Test("Missing optional sections decode rather than throw")
    func toleratesMissingSections() throws {
        let minimal = Data("""
        { "station": { "name": "S", "description": null,
                       "listen_url": "https://example.invalid/s.mp3" } }
        """.utf8)

        let decoded = try JSONDecoder().decode(RadioNowPlaying.self, from: minimal)

        #expect(decoded.nowPlaying == nil)
        #expect(decoded.playingNext == nil)
        #expect(decoded.songHistory == nil)
        #expect(decoded.listeners == nil)
    }
}
