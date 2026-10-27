import Foundation

nonisolated enum UITestFixtures {
  static let coreSongs: [Song] = [
    song(
      id: "ui-song-wake-me-up",
      title: "Wake Me Up Before You Go-Go",
      originalArtists: ["Wham!"]
    ),
    song(
      id: "ui-song-hero",
      title: "Hero",
      originalArtists: ["Mili"]
    ),
    song(
      id: "ui-song-cure-for-me",
      title: "Cure For Me",
      originalArtists: ["AURORA"]
    ),
    song(
      id: "ui-song-be-my-star",
      title: "Be My Star",
      originalArtists: ["LEVEL NINE"]
    ),
    song(
      id: "ui-song-young-and-beautiful",
      title: "Young and Beautiful",
      originalArtists: ["Lana Del Rey"]
    ),
    song(
      id: "ui-song-send-me-an-angel",
      title: "Send Me an Angel",
      originalArtists: ["Scorpions"]
    ),
  ]

  static func song(
    id: String,
    title: String,
    originalArtists: [String],
    coverArtists: [String] = ["Neuro"],
    duration: Int = 210,
    userUploaded: Bool = true
  ) -> Song {
    Song(
      id: id,
      title: title,
      duration: duration,
      absolutePath: nil,
      cloudflareID: nil,
      coverArt: nil,
      originalArtists: originalArtists,
      coverArtists: coverArtists,
      userUploaded: userUploaded
    )
  }

  static func song(
    id: String,
    title: String,
    artist: String,
    duration: Int = 210,
    userUploaded: Bool = true
  ) -> Song {
    song(
      id: id,
      title: title,
      originalArtists: [artist],
      duration: duration,
      userUploaded: userUploaded
    )
  }

  static func playlist(id: String, name: String, songs: [Song]) -> Playlist {
    Playlist(
      id: id,
      name: name,
      songCount: songs.count,
      media: nil,
      mosaicMedia: nil,
      songListDTOs: songs
    )
  }
}
