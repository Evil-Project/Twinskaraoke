import Foundation

nonisolated enum StorageHost {
  static var base: String {
    isChinaRegion ? "https://storage.neurokaraoke.com.cn" : "https://storage.neurokaraoke.com"
  }

  static var images: String {
    isChinaRegion ? "https://images.neurokaraoke.com.cn" : "https://images.neurokaraoke.com"
  }

  static var api: String {
    isChinaRegion ? "https://api.neurokaraoke.com.cn" : "https://api.neurokaraoke.com"
  }

  static var idk: String {
    isChinaRegion ? "https://idk.neurokaraoke.com.cn" : "https://idk.neurokaraoke.com"
  }

  /// The web player, whose pages are what a shared link opens. Song pages
  /// carry their own link preview (title, artwork, description).
  static let webPlayer = "https://twinskaraoke.com"

  /// The web player's page for a song, or `nil` for a personal upload, which
  /// has no public page to open.
  static func webPage(for song: Song) -> URL? {
    guard song.userUploaded != true else { return nil }
    return URL(string: webPlayer)?.appending(path: "song/\(song.id)")
  }

  private static var isChinaRegion: Bool { resolvedIsChinaRegion }

  /// Resolved once per process: the `nk.storageRegion` override is a debug key
  /// with no in-app settings UI, so a region change requires an app restart.
  private static let resolvedIsChinaRegion: Bool = {
    if let override = UserDefaults.standard.string(forKey: "nk.storageRegion") {
      return override == "cn"
    }

    let region = Locale.current.region?.identifier ?? Locale.current.identifier
    return region.uppercased() == "CN"
  }()
}
