import Combine
import Foundation
import SwiftUI

@MainActor
final class FavoritesManager: ObservableObject {
  static let shared = FavoritesManager()
  @Published private(set) var favoriteIDs: Set<String> = []
  private var inFlight: Set<String> = []
  private var loaded = false
  private static let base = "https://api.neurokaraoke.com/api/user/favorites"
  private var token: String? {
    UserDefaults.standard.string(forKey: "nk.token")
  }
  func isFavorite(_ songID: String) -> Bool { favoriteIDs.contains(songID) }
  func loadIfNeeded() {
    guard !loaded, token != nil else { return }
    loaded = true
    Task { await load() }
  }
  func reload() {
    Task { await load() }
  }
  func clear() {
    favoriteIDs = []
    loaded = false
  }
  func toggle(songID: String) {
    guard let token else { return }
    guard !inFlight.contains(songID) else { return }
    let wasFavorite = favoriteIDs.contains(songID)
    if wasFavorite {
      favoriteIDs.remove(songID)
    } else {
      favoriteIDs.insert(songID)
    }
    inFlight.insert(songID)
    Task {
      let ok = await send(songID: songID, add: !wasFavorite, token: token)
      await MainActor.run {
        inFlight.remove(songID)
        if !ok {
          if wasFavorite {
            favoriteIDs.insert(songID)
          } else {
            favoriteIDs.remove(songID)
          }
        }
      }
    }
  }
  private func load() async {
    guard let token else { return }
    guard let url = URL(string: Self.base) else { return }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    guard let (data, resp) = try? await URLSession.shared.data(for: req),
      let http = resp as? HTTPURLResponse, http.statusCode == 200
    else { return }
    let ids = Self.parseIDs(from: data)
    await MainActor.run { self.favoriteIDs = Set(ids) }
  }
  private func send(songID: String, add: Bool, token: String) async -> Bool {
    guard let url = URL(string: "\(Self.base)/\(songID)") else { return false }
    var req = URLRequest(url: url)
    req.httpMethod = add ? "PUT" : "DELETE"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("0", forHTTPHeaderField: "Content-Length")
    guard let (_, resp) = try? await URLSession.shared.data(for: req),
      let http = resp as? HTTPURLResponse
    else { return false }
    return (200..<300).contains(http.statusCode)
  }
  private static func parseIDs(from data: Data) -> [String] {
    if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
      return arr.compactMap { $0["id"] as? String ?? $0["songId"] as? String }
    }
    if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
      return arr
    }
    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let arr = (obj["favorites"] ?? obj["items"]) as? [[String: Any]]
    {
      return arr.compactMap { $0["id"] as? String ?? $0["songId"] as? String }
    }
    return []
  }
}
