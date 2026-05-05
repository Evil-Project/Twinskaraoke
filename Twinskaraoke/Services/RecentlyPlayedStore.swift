import Combine
import Foundation
import SwiftUI

@MainActor
final class RecentlyPlayedStore: ObservableObject {
  static let shared = RecentlyPlayedStore()
  private static let storageKey = "nk.recentlyPlayed.playlists.v1"
  private static let limit = 20
  @Published private(set) var playlists: [Playlist] = []
  private init() {
    load()
  }
  func record(_ playlist: Playlist) {
    var next = playlists.filter { $0.id != playlist.id }
    next.insert(playlist, at: 0)
    if next.count > Self.limit { next = Array(next.prefix(Self.limit)) }
    playlists = next
    save()
  }
  func reset() {
    playlists = []
    UserDefaults.standard.removeObject(forKey: Self.storageKey)
  }
  private func load() {
    guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
    if let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
      playlists = decoded
    }
  }
  private func save() {
    if let data = try? JSONEncoder().encode(playlists) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}
