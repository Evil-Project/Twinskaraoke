import Foundation
import Testing

@testable import Twinskaraoke_Watch_App
struct WatchSongModelTests {
  @Test func songImageURL_withCloudflareId() {
    let song = Song(
      id: "1", title: "Test", duration: 180, absolutePath: "/test.mp3",
      coverArt: nil, coverArtists: nil, originalArtists: nil, cloudflareId: "cf-abc123")
    #expect(song.imageURL?.absoluteString == "https://images.neurokaraoke.com/cf-abc123/public")
  }
  @Test func songImageURL_withCoverArt() {
    let song = Song(
      id: "2", title: "Test", duration: 120, absolutePath: "/test.mp3",
      coverArt: SongMedia(absolutePath: "/img/cover.jpg"),
      coverArtists: nil, originalArtists: nil, cloudflareId: nil)
    #expect(
      song.imageURL?.absoluteString == "https://images.neurokaraoke.com/img/cover.jpg/quality=95")
  }
  @Test func songAudioURL_stripsLeadingSlash() {
    let song = Song(
      id: "3", title: "Test", duration: 200, absolutePath: "/songs/track.mp3",
      coverArt: nil, coverArtists: nil, originalArtists: nil, cloudflareId: nil)
    #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/songs/track.mp3")
  }
  @Test func songArtistName_withOriginalArtists() {
    let song = Song(
      id: "4", title: "Test", duration: 100, absolutePath: "/t.mp3",
      coverArt: nil, coverArtists: ["Cover"], originalArtists: ["A", "B"], cloudflareId: nil)
    #expect(song.artistName == "A, B")
  }
  @Test func songArtistName_fallsToCoverArtists() {
    let song = Song(
      id: "5", title: "Test", duration: 100, absolutePath: "/t.mp3",
      coverArt: nil, coverArtists: ["Cover Artist"], originalArtists: nil, cloudflareId: nil)
    #expect(song.artistName == "Cover Artist")
  }
  @Test func songArtistName_fallsToUnknown() {
    let song = Song(
      id: "6", title: "Test", duration: 100, absolutePath: "/t.mp3",
      coverArt: nil, coverArtists: nil, originalArtists: nil, cloudflareId: nil)
    #expect(song.artistName == "Unknown Artist")
  }
  @Test func songDurationText() {
    let song = Song(
      id: "7", title: "Test", duration: 185, absolutePath: "/t.mp3",
      coverArt: nil, coverArtists: nil, originalArtists: nil, cloudflareId: nil)
    #expect(song.durationText == "3:05")
  }
  @Test func songEquality_byId() {
    let a = Song(
      id: "same", title: "A", duration: 1, absolutePath: "/a.mp3",
      coverArt: nil, coverArtists: nil, originalArtists: nil, cloudflareId: nil)
    let b = Song(
      id: "same", title: "B", duration: 2, absolutePath: "/b.mp3",
      coverArt: nil, coverArtists: nil, originalArtists: nil, cloudflareId: nil)
    #expect(a == b)
  }
  @Test func searchSongItem_toSong_withAbsolutePath() {
    let item = SearchSongItem(
      id: "s1", title: "Search Song", duration: 200,
      absolutePath: "/songs/search.mp3",
      originalArtists: ["Artist"], coverArtists: nil,
      coverArt: SearchMedia(absolutePath: "/img/s.jpg"),
      cloudflareId: nil)
    let song = item.toSong()
    #expect(song != nil)
    #expect(song?.id == "s1")
    #expect(song?.absolutePath == "/songs/search.mp3")
  }
  @Test func searchSongItem_toSong_withoutAbsolutePathReturnsNil() {
    let item = SearchSongItem(
      id: "s2", title: "No Path", duration: 100,
      absolutePath: nil,
      originalArtists: nil, coverArtists: nil,
      coverArt: nil, cloudflareId: nil)
    #expect(item.toSong() == nil)
  }
}

struct WatchGuestIdentityTests {
  @Test func guestIdentityIsStable() {
    let first = GuestIdentity.current
    let second = GuestIdentity.current
    #expect(first == second)
    #expect(!first.isEmpty)
  }
}
