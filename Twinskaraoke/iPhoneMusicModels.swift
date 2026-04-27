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

struct PressableButtonStyle: ButtonStyle {
  var scale: CGFloat = 0.97
  var dim: Double = 0.7
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? scale : 1.0)
      .opacity(configuration.isPressed ? dim : 1.0)
      .animation(
        .spring(response: 0.32, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

struct AppleMusicProgressBar: View {
  @Binding var progress: Double
  @Binding var isScrubbing: Bool
  let onSeekEnd: (Double) -> Void
  var trackColor: Color = .white.opacity(0.28)
  var fillColor: Color = .white
  var idleHeight: CGFloat = 5
  var activeHeight: CGFloat = 9
  var body: some View {
    GeometryReader { geo in
      let height: CGFloat = isScrubbing ? activeHeight : idleHeight
      ZStack(alignment: .leading) {
        Capsule().fill(trackColor)
        Capsule()
          .fill(fillColor)
          .frame(width: max(0, geo.size.width * CGFloat(min(max(progress, 0), 1))))
      }
      .frame(height: height)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if !isScrubbing { isScrubbing = true }
            progress = max(0, min(1, value.location.x / geo.size.width))
          }
          .onEnded { _ in
            onSeekEnd(progress)
            isScrubbing = false
          }
      )
      .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isScrubbing)
    }
    .frame(height: 24)
  }
}

struct NowPlayingBar: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    if let song = audioManager.currentSong {
      Button {
        audioManager.showFullScreen = true
      } label: {
        nowPlayingContent(song: song)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.85))
    }
  }

  @ViewBuilder
  private func nowPlayingContent(song: PhoneSong) -> some View {
    VStack(spacing: 0) {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Rectangle().fill(.primary.opacity(0.08))
            Rectangle()
              .fill(.pink)
              .frame(width: geo.size.width * CGFloat(audioManager.progress))
              .animation(.linear(duration: 0.5), value: audioManager.progress)
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
              Group {
                if #available(iOS 17.0, *) {
                  Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                } else {
                  Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.opacity)
                }
              }
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
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .shadow(color: .black.opacity(0.1), radius: 6, y: 1)
      .padding(.horizontal, 6)
      .padding(.bottom, 2)
  }
}

struct MarqueeText: View {
  let text: String
  let font: Font
  let color: Color
  @State private var animate = false
  @State private var textWidth: CGFloat = 0
  @State private var containerWidth: CGFloat = 0
  private let gap: CGFloat = 48

  var body: some View {
    Text(text)
      .font(font)
      .lineLimit(1)
      .opacity(0)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(
        GeometryReader { geo in
          let needsScroll = containerWidth > 0 && textWidth > containerWidth
          ZStack(alignment: .leading) {
            if needsScroll {
              HStack(spacing: gap) {
                Text(text).font(font).foregroundColor(color).fixedSize()
                Text(text).font(font).foregroundColor(color).fixedSize()
              }
              .offset(x: animate ? -(textWidth + gap) : 0)
              .animation(
                .linear(duration: Double(textWidth + gap) / 35)
                  .delay(1.0)
                  .repeatForever(autoreverses: false),
                value: animate
              )
              .id(text)
            } else {
              Text(text).font(font).foregroundColor(color).fixedSize()
            }
          }
          .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
          .clipped()
          .mask(
            LinearGradient(
              stops: needsScroll
                ? [
                  .init(color: .clear, location: 0),
                  .init(color: .black, location: 0.04),
                  .init(color: .black, location: 0.96),
                  .init(color: .clear, location: 1),
                ]
                : [
                  .init(color: .black, location: 0),
                  .init(color: .black, location: 1),
                ],
              startPoint: .leading, endPoint: .trailing
            )
          )
          .onAppear {
            containerWidth = geo.size.width
            if textWidth > geo.size.width { animate = true }
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
        if containerWidth > 0 { animate = w > containerWidth }
      }
  }
}

private struct TextWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct FullScreenPlayerView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @State private var isFavorite = false
  @State private var dragOffset: CGFloat = 0
  @State private var isVolumeScrubbing = false
  var body: some View {
    if let song = audioManager.currentSong {
      GeometryReader { geo in
        let artSize = min(geo.size.width - 64, geo.size.height * 0.45, 360)

        VStack(spacing: 0) {
            Button {
              audioManager.showFullScreen = false
            } label: {
              Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            LoadingImage(url: song.imageURL, cornerRadius: 12, contentMode: .fill)
              .frame(width: artSize, height: artSize)
              .scaleEffect(audioManager.isPlaying ? 1.0 : 0.82)
              .shadow(
                color: .black.opacity(audioManager.isPlaying ? 0.45 : 0.2),
                radius: audioManager.isPlaying ? 28 : 14,
                y: audioManager.isPlaying ? 18 : 8
              )
              .animation(
                .spring(response: 0.55, dampingFraction: 0.72), value: audioManager.isPlaying
              )
              .id(song.id)
              .transition(.opacity.combined(with: .scale(scale: 0.92)))
              .animation(.easeInOut(duration: 0.35), value: song.id)
              .frame(maxWidth: .infinity)

            Spacer(minLength: 16)

            HStack(alignment: .center, spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                MarqueeText(
                  text: song.displayTitle,
                  font: .system(size: 22, weight: .bold),
                  color: .white
                )
                if !song.displayCoverArtist.isEmpty {
                  Text(song.displayCoverArtist)
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                }
              }
              Spacer(minLength: 8)
              Button {
                isFavorite.toggle()
              } label: {
                Group {
                  if #available(iOS 17.0, *) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                      .contentTransition(.symbolEffect(.replace))
                  } else {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                  }
                }
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(isFavorite ? .pink : .white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: Circle())
              }
              .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.85))
            }
            .padding(.horizontal, 32)
            .id(song.id)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeInOut(duration: 0.35), value: song.id)

            AppleMusicProgressBar(
              progress: $audioManager.progress,
              isScrubbing: $audioManager.isEditingProgress,
              onSeekEnd: { p in audioManager.seek(to: p) }
            )
            .padding(.horizontal, 32)
            .padding(.top, 16)

            HStack {
              Text(formattedTime(audioManager.progress * Double(song.duration)))
              Spacer()
              Text(
                "-"
                  + formattedTime(
                    max(0, Double(song.duration) - audioManager.progress * Double(song.duration))))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(
              audioManager.isEditingProgress ? .white : .white.opacity(0.55)
            )
            .scaleEffect(audioManager.isEditingProgress ? 1.12 : 1.0, anchor: .center)
            .animation(
              .spring(response: 0.3, dampingFraction: 0.85), value: audioManager.isEditingProgress
            )
            .padding(.horizontal, 32)
            .padding(.top, 2)

            HStack(spacing: 0) {
              Button {
                audioManager.playPrevious()
              } label: {
                Image(systemName: "backward.fill")
                  .font(.system(size: 32))
                  .foregroundColor(.white)
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
              Button {
                audioManager.togglePlayPause()
              } label: {
                Group {
                  if #available(iOS 17.0, *) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                      .contentTransition(.symbolEffect(.replace))
                  } else {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                      .contentTransition(.opacity)
                  }
                }
                .font(.system(size: 48))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
              }
              .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
              Button {
                audioManager.playNextOrRandom()
              } label: {
                Image(systemName: "forward.fill")
                  .font(.system(size: 32))
                  .foregroundColor(.white)
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
              Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
              AppleMusicProgressBar(
                progress: $audioManager.volume,
                isScrubbing: $isVolumeScrubbing,
                onSeekEnd: { _ in },
                trackColor: .white.opacity(0.28),
                fillColor: .white,
                idleHeight: 5,
                activeHeight: 9
              )
              Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 32)

            HStack(spacing: 0) {
              Button {
              } label: {
                Image(systemName: "quote.bubble")
                  .font(.system(size: 22))
                  .foregroundColor(.white.opacity(0.85))
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55))
              Button {
              } label: {
                Image(systemName: "airplayaudio")
                  .font(.system(size: 22))
                  .foregroundColor(.white.opacity(0.85))
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55))
              Button {
              } label: {
                Image(systemName: "list.bullet")
                  .font(.system(size: 22))
                  .foregroundColor(.white.opacity(0.85))
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55))
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)

            Spacer(minLength: 8)
          }
        .frame(width: geo.size.width, height: geo.size.height)
        .background(
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
          }
          .ignoresSafeArea()
        )
        .offset(y: max(0, dragOffset))
        .scaleEffect(1 - min(0.04, dragOffset / 2000))
        .opacity(1 - min(0.18, dragOffset / 1200))
        .gesture(
          DragGesture(minimumDistance: 12)
            .onChanged { value in
              let v = value.translation.height
              let h = abs(value.translation.width)
              if v > 0 && v > h * 1.5 {
                dragOffset = v
              }
            }
            .onEnded { value in
              if value.translation.height > 120 || value.predictedEndTranslation.height > 220 {
                audioManager.showFullScreen = false
                dragOffset = 0
              } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                  dragOffset = 0
                }
              }
            }
        )
      }
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
