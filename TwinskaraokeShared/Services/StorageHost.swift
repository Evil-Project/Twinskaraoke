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
