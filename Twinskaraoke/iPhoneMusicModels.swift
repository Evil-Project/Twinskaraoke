//
//  iPhoneMusicModels.swift
//  Twinskaraoke
//
//  Created by xiaoyuan on 2026/4/26.
//
import AVFoundation
import Combine
import Foundation
import SwiftUI

struct PhoneSong: Codable, Identifiable, Equatable {
  let id: String
  let title: String
  let duration: Int
  let absolutePath: String?
  let cloudflareId: String?
  let coverArt: Media?
  let originalArtists: [String]?
  let coverArtists: [String]?
  var imageURL: URL? {
    if let cfId = cloudflareId {
      return URL(string: "https://images.neurokaraoke.com/\(cfId)/public")
    }
    guard let path = coverArt?.absolutePath else { return nil }
    return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
  }
  var audioURL: URL? {
    guard let path = absolutePath else { return nil }
    let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
    return URL(string: "https://storage.neurokaraoke.com/\(cleanPath)")
  }
  var displayTitle: String {
    let artists = originalArtists?.joined(separator: ", ") ?? ""
    return artists.isEmpty ? title : "\(title) - \(artists)"
  }
  var displayCoverArtist: String {
    coverArtists?.joined(separator: ", ") ?? ""
  }
  static func == (lhs: PhoneSong, rhs: PhoneSong) -> Bool { lhs.id == rhs.id }
}

struct Playlist: Codable, Identifiable {
  let id: String
  let name: String
  let songCount: Int
  let mosaicMedia: [Media]?
  let songListDTOs: [PhoneSong]?
  var imageURL: URL? {
    guard let path = mosaicMedia?.first?.absolutePath else { return nil }
    return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
  }
}

struct Media: Codable {
  let absolutePath: String
}

struct PhoneSearchResponse: Codable {
  let items: [PhoneSong]
}

struct NowPlayingBar: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    if let song = audioManager.currentSong {
      VStack(spacing: 0) {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Rectangle().fill(.primary.opacity(0.08))
            Rectangle()
              .fill(.pink)
              .frame(width: geo.size.width * CGFloat(audioManager.progress))
          }
        }
        .frame(height: 2)
        HStack(spacing: 10) {
          LoadingImage(url: song.imageURL, cornerRadius: 4)
            .frame(width: 36, height: 36)
            .clipped()
            .cornerRadius(4)
          VStack(alignment: .leading, spacing: 1) {
            MarqueeText(
              text: song.displayTitle, font: .system(size: 13, weight: .semibold), color: .primary)
            if !song.displayCoverArtist.isEmpty {
              Text(song.displayCoverArtist)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
          }
          Spacer()
          HStack(spacing: 14) {
            Button {
              audioManager.playPrevious()
            } label: {
              Image(systemName: "backward.end.fill").font(.system(size: 14)).foregroundColor(
                .primary)
            }
            .buttonStyle(.plain)
            Button {
              audioManager.togglePlayPause()
            } label: {
              Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18)).foregroundColor(.primary).frame(width: 20)
            }
            .buttonStyle(.plain)
            Button {
              audioManager.playNextOrRandom()
            } label: {
              Image(systemName: "forward.end.fill").font(.system(size: 14)).foregroundColor(
                .primary)
            }
            .buttonStyle(.plain)
          }
          .padding(.trailing, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .shadow(color: .black.opacity(0.1), radius: 6, y: 1)
      .padding(.horizontal, 6)
      .padding(.bottom, 2)
      .onTapGesture { audioManager.showFullScreen = true }
    }
  }
}

struct MarqueeText: View {
  let text: String
  let font: Font
  let color: Color
  @State private var animate = false
  @State private var textWidth: CGFloat = 0
  @State private var containerWidth: CGFloat = 0
  var body: some View {
    Text(text)
      .font(font)
      .hidden()
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(
        GeometryReader { geo in
          let needsScroll = textWidth > geo.size.width
          ZStack(alignment: .leading) {
            if needsScroll {
              Text(text + "          " + text)
                .font(font)
                .foregroundColor(color)
                .fixedSize()
                .offset(x: animate ? -(textWidth + 80) : 0)
                .animation(
                  .linear(duration: Double(textWidth) / 35)
                    .delay(1.0)
                    .repeatForever(autoreverses: false),
                  value: animate
                )
            } else {
              Text(text)
                .font(font)
                .foregroundColor(color)
                .fixedSize()
            }
          }
          .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
          .clipped()
          .onAppear {
            containerWidth = geo.size.width
            animate = needsScroll
          }
        }
      )
      .background(
        Text(text)
          .font(font)
          .fixedSize()
          .hidden()
          .background(
            GeometryReader { t in
              Color.clear.preference(key: TextWidthKey.self, value: t.size.width)
            })
      )
      .onPreferenceChange(TextWidthKey.self) { w in
        textWidth = w
        animate = w > containerWidth
      }
  }
}

private struct TextWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct FullScreenPlayerView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    if let song = audioManager.currentSong {
      GeometryReader { geo in
        ZStack {
          Color.black
          LoadingImage(url: song.imageURL, cornerRadius: 0, contentMode: .fill)
            .blur(radius: 60)
            .scaleEffect(1.2)
            .opacity(0.5)
          LinearGradient(
            colors: [.black.opacity(0.3), .black.opacity(0.5), .black.opacity(0.8)],
            startPoint: .top, endPoint: .bottom
          )
          VStack(spacing: 0) {
            HStack {
              Button {
                audioManager.showFullScreen = false
              } label: {
                Image(systemName: "chevron.down")
                  .font(.system(size: 20, weight: .medium))
                  .foregroundColor(.white.opacity(0.8))
                  .padding(8)
              }
              Spacer()
              Button {
              } label: {
                Image(systemName: "ellipsis")
                  .font(.system(size: 20, weight: .medium))
                  .foregroundColor(.white.opacity(0.8))
                  .padding(8)
              }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            LoadingImage(url: song.imageURL, cornerRadius: 12, contentMode: .fill)
              .frame(width: 320, height: 320)
              .cornerRadius(12)
              .shadow(color: .black.opacity(0.4), radius: 24, y: 16)

            Spacer()

            VStack(spacing: 24) {
              HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                  MarqueeText(
                    text: song.displayTitle, font: .system(size: 24, weight: .bold), color: .white)
                  if !song.displayCoverArtist.isEmpty {
                    Text(song.displayCoverArtist)
                      .font(.system(size: 18))
                      .foregroundColor(.white.opacity(0.6))
                      .lineLimit(1)
                  }
                }
                Spacer(minLength: 16)
              }
              .padding(.horizontal, 36)

              VStack(spacing: 8) {
                Slider(
                  value: Binding(
                    get: { audioManager.progress },
                    set: { audioManager.progress = $0 }
                  ),
                  in: 0...1,
                  onEditingChanged: { editing in
                    audioManager.isEditingProgress = editing
                    if !editing {
                      audioManager.seek(to: audioManager.progress)
                    }
                  }
                )
                .tint(.white)
                .padding(.horizontal, 32)
                HStack {
                  Text(formattedTime(audioManager.progress * Double(song.duration)))
                  Spacer()
                  Text(formattedTime(Double(song.duration)))
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 32)
              }

              HStack(spacing: 0) {
                Button {
                  audioManager.playPrevious()
                } label: {
                  Image(systemName: "backward.fill").font(.system(size: 32)).foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                }
                Button {
                  audioManager.togglePlayPause()
                } label: {
                  Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                Button {
                  audioManager.playNextOrRandom()
                } label: {
                  Image(systemName: "forward.fill").font(.system(size: 32)).foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                }
              }
              .padding(.horizontal, 32)
              .padding(.bottom, 24)
            }
          }
          .padding(.top, geo.safeAreaInsets.top)
          .padding(.bottom, geo.safeAreaInsets.bottom)
        }
      }
      .ignoresSafeArea()
      .colorScheme(.dark)
    }
  }
  private func formattedTime(_ seconds: Double) -> String {
    let s = Int(seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
  }
}

class HomeViewModel: ObservableObject {
  @Published var trending: [PhoneSong] = []
  @Published var suggestions: [PhoneSong] = []
  @Published var recentPlaylist: Playlist?
  @Published var isLoading = false
  func fetchHomeData() {
    isLoading = true
    let group = DispatchGroup()
    group.enter()
    fetchData(url: "https://api.neurokaraoke.com/api/explore/trendings?days=7&take=20") {
      (i: [PhoneSong]?) in
      if let i = i { DispatchQueue.main.async { self.trending = i } }
      group.leave()
    }
    group.enter()
    fetchData(url: "https://api.neurokaraoke.com/api/user/suggestions?take=20") {
      (i: [PhoneSong]?) in
      if let i = i { DispatchQueue.main.async { self.suggestions = i } }
      group.leave()
    }
    group.enter()
    fetchData(url: "https://api.neurokaraoke.com/api/playlist/recent") { (i: Playlist?) in
      if let i = i { DispatchQueue.main.async { self.recentPlaylist = i } }
      group.leave()
    }
    group.notify(queue: .main) { self.isLoading = false }
  }
  private func fetchData<T: Codable>(url: String, completion: @escaping (T?) -> Void) {
    guard let u = URL(string: url) else {
      completion(nil)
      return
    }
    var r = URLRequest(url: u)
    r.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: r) { d, _, _ in
      if let d = d, let dec = try? JSONDecoder().decode(T.self, from: d) {
        completion(dec)
      } else {
        completion(nil)
      }
    }.resume()
  }
}

class PhonePlaylistsViewModel: ObservableObject {
  @Published var playlists: [Playlist] = []
  @Published var isLoading = false
  func fetchPlaylists() {
    guard
      let url = URL(
        string:
          "https://api.neurokaraoke.com/api/playlists?startIndex=0&pageSize=25&search=&sortBy=&sortDescending=False&isSetlist=True&year=0"
      )
    else { return }
    isLoading = true
    var r = URLRequest(url: url)
    r.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: r) { d, _, _ in
      if let d = d, let dec = try? JSONDecoder().decode([Playlist].self, from: d) {
        DispatchQueue.main.async {
          self.playlists = dec
          self.isLoading = false
        }
      } else {
        DispatchQueue.main.async { self.isLoading = false }
      }
    }.resume()
  }
}

class PhoneSearchViewModel: ObservableObject {
  @Published var results: [PhoneSong] = []
  @Published var searchText = ""
  @Published var isSearching = false
  private var cancellables = Set<AnyCancellable>()
  init() {
    $searchText
      .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
      .removeDuplicates()
      .sink { [weak self] t in
        if !t.isEmpty { self?.search(t) } else { self?.results = [] }
      }
      .store(in: &cancellables)
  }
  func search(_ q: String) {
    guard let u = URL(string: "https://api.neurokaraoke.com/api/songs") else { return }
    isSearching = true
    var r = URLRequest(url: u)
    r.httpMethod = "POST"
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
    r.httpBody = try? JSONSerialization.data(withJSONObject: [
      "page": 1, "pageSize": 30, "search": q,
    ])
    URLSession.shared.dataTask(with: r) { d, _, _ in
      if let d = d, let dec = try? JSONDecoder().decode(PhoneSearchResponse.self, from: d) {
        DispatchQueue.main.async {
          self.results = dec.items
          self.isSearching = false
        }
      } else {
        DispatchQueue.main.async { self.isSearching = false }
      }
    }.resume()
  }
}
