import Foundation

nonisolated extension StorageHost {
  /// The web player's page for a song, or `nil` for a personal upload, which
  /// has no public page to open.
  static func webPage(for song: Song) -> URL? {
    guard song.userUploaded != true else { return nil }
    return URL(string: webPlayer)?.appending(path: "song/\(song.id)")
  }

}
