import CryptoKit
import Foundation

nonisolated enum SongStorageKey {
  private static let hashPrefix = "__nksha256_"
  private static let allowed = CharacterSet.alphanumerics.union(
    CharacterSet(charactersIn: "-_")
  )

  static func component(for songID: String) -> String {
    if !songID.isEmpty,
       songID != ".",
       songID != "..",
       !songID.hasPrefix(hashPrefix),
       songID.utf8.count <= 200,
       songID.unicodeScalars.allSatisfy({ allowed.contains($0) })
    {
      return songID
    }

    let digest = SHA256.hash(data: Data(songID.utf8))
    return hashPrefix + digest.map { String(format: "%02x", $0) }.joined()
  }

  static func components(for songIDs: Set<String>) -> Set<String> {
    Set(songIDs.map(component(for:)))
  }
}
