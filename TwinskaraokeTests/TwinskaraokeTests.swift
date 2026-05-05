import Foundation
import Testing

@testable import Twinskaraoke
struct SongModelTests {
  @Test func songImageURL_withCloudflareId() {
    let song = Song(
      id: "1", title: "Test", duration: 180, absolutePath: "/test.mp3",
      cloudflareID: "cf-abc123", coverArt: nil, originalArtists: nil, coverArtists: nil)
    #expect(song.imageURL?.absoluteString == "https://images.neurokaraoke.com/cf-abc123/public")
  }
  @Test func songImageURL_withCoverArt() {
    let song = Song(
      id: "2", title: "Test", duration: 120, absolutePath: nil,
      cloudflareID: nil, coverArt: Media(absolutePath: "/img/cover.jpg"),
      originalArtists: nil, coverArtists: nil)
    #expect(
      song.imageURL?.absoluteString == "https://images.neurokaraoke.com/img/cover.jpg/quality=95")
  }
  @Test func songImageURL_withNeitherReturnsNil() {
    let song = Song(
      id: "3", title: "Test", duration: 60, absolutePath: nil,
      cloudflareID: nil, coverArt: nil, originalArtists: nil, coverArtists: nil)
    #expect(song.imageURL == nil)
  }
  @Test func songAudioURL_stripsLeadingSlash() {
    let song = Song(
      id: "4", title: "Test", duration: 200, absolutePath: "/songs/track.mp3",
      cloudflareID: nil, coverArt: nil, originalArtists: nil, coverArtists: nil)
    #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/songs/track.mp3")
  }
  @Test func songAudioURL_noLeadingSlash() {
    let song = Song(
      id: "5", title: "Test", duration: 200, absolutePath: "songs/track.mp3",
      cloudflareID: nil, coverArt: nil, originalArtists: nil, coverArtists: nil)
    #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/songs/track.mp3")
  }
  @Test func songDisplayTitle_withArtists() {
    let song = Song(
      id: "6", title: "Song", duration: 100, absolutePath: nil,
      cloudflareID: nil, coverArt: nil, originalArtists: ["Artist A", "Artist B"],
      coverArtists: nil)
    #expect(song.displayTitle == "Song - Artist A, Artist B")
  }
  @Test func songDisplayTitle_withoutArtists() {
    let song = Song(
      id: "7", title: "Solo", duration: 100, absolutePath: nil,
      cloudflareID: nil, coverArt: nil, originalArtists: nil, coverArtists: nil)
    #expect(song.displayTitle == "Solo")
  }
  @Test func songEquality_byId() {
    let a = Song(
      id: "same", title: "A", duration: 1, absolutePath: nil,
      cloudflareID: nil, coverArt: nil, originalArtists: nil, coverArtists: nil)
    let b = Song(
      id: "same", title: "B", duration: 2, absolutePath: nil,
      cloudflareID: nil, coverArt: nil, originalArtists: nil, coverArtists: nil)
    #expect(a == b)
  }
  @Test func playlistImageURL() {
    let playlist = Playlist(
      id: "p1", name: "Test", songCount: 5,
      mosaicMedia: [Media(absolutePath: "/img/mosaic.jpg")], songListDTOs: nil)
    #expect(
      playlist.imageURL?.absoluteString
        == "https://images.neurokaraoke.com/img/mosaic.jpg/quality=95")
  }
}

struct TimeSpanParserTests {
  @Test func parsesStandardFormat() {
    let result = TimeSpanParser.parse("00:01:23.4560000")
    #expect(result != nil)
    if let r = result {
      #expect(abs(r - 83.456) < 0.001)
    }
  }
  @Test func parsesZero() {
    let result = TimeSpanParser.parse("00:00:00.0000000")
    #expect(result != nil)
    if let r = result {
      #expect(abs(r) < 0.001)
    }
  }
  @Test func parsesSubSecond() {
    let result = TimeSpanParser.parse("00:00:00.8400000")
    #expect(result != nil)
    if let r = result {
      #expect(abs(r - 0.84) < 0.001)
    }
  }
  @Test func parsesMinutesAndSeconds() {
    let result = TimeSpanParser.parse("00:04:29.0000000")
    #expect(result != nil)
    if let r = result {
      #expect(abs(r - 269.0) < 0.001)
    }
  }
  @Test func parsesWithHours() {
    let result = TimeSpanParser.parse("01:30:00.0000000")
    #expect(result != nil)
    if let r = result {
      #expect(abs(r - 5400.0) < 0.001)
    }
  }
  @Test func returnsNilForInvalidFormat() {
    #expect(TimeSpanParser.parse("invalid") == nil)
    #expect(TimeSpanParser.parse("00:00") == nil)
    #expect(TimeSpanParser.parse("") == nil)
  }
}

struct GuestIdentityTests {
  @Test func guestIdentityIsStable() {
    let first = GuestIdentity.current
    let second = GuestIdentity.current
    #expect(first == second)
    #expect(!first.isEmpty)
  }
}
private func makePlaylist(id: String, name: String = "P", count: Int = 1) -> Playlist {
  Playlist(id: id, name: name, songCount: count, mosaicMedia: nil, songListDTOs: nil)
}

@MainActor
struct RecentlyPlayedStoreTests {
  @Test func recordAddsToFront() async {
    let key = "nk.recentlyPlayed.playlists.v1"
    UserDefaults.standard.removeObject(forKey: key)
    let store = RecentlyPlayedStore.shared
    let a = makePlaylist(id: "test-a")
    let b = makePlaylist(id: "test-b")
    store.record(a)
    store.record(b)
    #expect(store.playlists.first?.id == "test-b")
    #expect(store.playlists.contains(where: { $0.id == "test-a" }))
  }
  @Test func recordDeduplicates() async {
    let store = RecentlyPlayedStore.shared
    let a = makePlaylist(id: "dup-a")
    let b = makePlaylist(id: "dup-b")
    store.record(a)
    store.record(b)
    store.record(a)
    let aOccurrences = store.playlists.filter { $0.id == "dup-a" }.count
    #expect(aOccurrences == 1)
    #expect(store.playlists.first?.id == "dup-a")
  }
  @Test func recordRespectsLimit() async {
    let store = RecentlyPlayedStore.shared
    for i in 0..<25 {
      store.record(makePlaylist(id: "limit-\(i)"))
    }
    #expect(store.playlists.count <= 20)
  }
  @Test func persistsAcrossInstances() async {
    let key = "nk.recentlyPlayed.playlists.v1"
    UserDefaults.standard.removeObject(forKey: key)
    let store = RecentlyPlayedStore.shared
    store.record(makePlaylist(id: "persist-1"))
    let data = UserDefaults.standard.data(forKey: key)
    #expect(data != nil)
    if let data {
      let decoded = try? JSONDecoder().decode([Playlist].self, from: data)
      #expect(decoded?.first?.id == "persist-1")
    }
  }
}

struct RadioNowPlayingDecodingTests {
  @Test func decodesRealApiPayload() throws {
    let json = """
    {
      "station": {
        "name": "Neuro 21 Station",
        "description": "Live radio",
        "listen_url": "https://radio.twinskaraoke.com/listen/neuro_21/radio.mp3"
      },
      "listeners": { "total": 14, "unique": 13 },
      "now_playing": {
        "song": {
          "id": "abc",
          "art": "https://example.com/art.jpg",
          "text": "Oasis - Wonderwall",
          "artist": "Oasis",
          "title": "Wonderwall"
        }
      },
      "playing_next": {
        "song": {
          "id": "def",
          "art": null,
          "text": "Next - Track",
          "artist": "Next",
          "title": "Track"
        }
      },
      "song_history": [
        {
          "song": {
            "id": "old1",
            "art": "https://example.com/old1.jpg",
            "text": "Old - One",
            "artist": "Old",
            "title": "One"
          }
        }
      ]
    }
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(RadioNowPlaying.self, from: json)
    #expect(decoded.station.name == "Neuro 21 Station")
    #expect(decoded.station.listenUrl.hasSuffix("radio.mp3"))
    #expect(decoded.listeners?.total == 14)
    #expect(decoded.nowPlaying?.song.title == "Wonderwall")
    #expect(decoded.playingNext?.song.title == "Track")
    #expect(decoded.songHistory?.count == 1)
  }
  @Test func toSongUsesTitleAndArtist() {
    let info = RadioNowPlaying.SongInfo(
      id: "x", art: nil, text: "raw", artist: "Artist A", title: "Title B", customFields: nil)
    let song = info.toSong(stationID: "neuro_21")
    #expect(song.id == "radio:neuro_21")
    #expect(song.title == "Title B")
    #expect(song.originalArtists == ["Artist A"])
  }
  @Test func toSongFallsBackToText() {
    let info = RadioNowPlaying.SongInfo(
      id: "x", art: nil, text: "Fallback text", artist: nil, title: nil, customFields: nil)
    let song = info.toSong(stationID: "neuro_21")
    #expect(song.title == "Fallback text")
  }
}

@MainActor
struct FavoritesManagerTests {
  @Test func isFavoriteReflectsState() {
    let mgr = FavoritesManager.shared
    let testID = "fav-test-\(UUID().uuidString)"
    #expect(!mgr.isFavorite(testID))
  }
  @Test func clearEmptiesFavorites() {
    let mgr = FavoritesManager.shared
    mgr.clear()
    #expect(mgr.favoriteIDs.isEmpty)
  }
}
