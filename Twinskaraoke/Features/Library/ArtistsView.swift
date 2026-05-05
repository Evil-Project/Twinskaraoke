import Combine
import Foundation
import SwiftUI

struct Artist: Codable, Identifiable, Equatable {
  let id: String
  let name: String
  let summary: String?
  let imagePath: String?
  let songCount: Int?
  let songListDTOs: [Song]?
  var imageURL: URL? {
    guard let path = imagePath, !path.isEmpty else { return nil }
    let cleanPath = path.hasPrefix("/") ? path : "/" + path
    return URL(string: "https://storage.neurokaraoke.com" + cleanPath)
  }
  static func == (lhs: Artist, rhs: Artist) -> Bool { lhs.id == rhs.id }
}
@MainActor
final class ArtistsViewModel: ObservableObject {
  @Published var artists: [Artist] = []
  @Published var isLoading = false
  @Published var canLoadMore = true
  private var page = 0
  private let pageSize = 25
  func fetchInitial() {
    guard artists.isEmpty else { return }
    page = 0
    canLoadMore = true
    load(reset: true)
  }
  func loadMoreIfNeeded(current: Artist) {
    guard let idx = artists.firstIndex(of: current) else { return }
    if idx >= artists.count - 5 && !isLoading && canLoadMore {
      load(reset: false)
    }
  }
  private func load(reset: Bool) {
    let startIndex = page * pageSize
    let urlString =
      "https://api.neurokaraoke.com/api/artists?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=Name&sortDescending=False"
    guard let url = URL(string: urlString) else { return }
    isLoading = true
    var request = URLRequest(url: url)
    request.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor in
        guard let self = self else { return }
        if let data, let decoded = try? JSONDecoder().decode([Artist].self, from: data) {
          if reset {
            self.artists = decoded
          } else {
            let existing = Set(self.artists.map { $0.id })
            self.artists += decoded.filter { !existing.contains($0.id) }
          }
          self.page += 1
          self.canLoadMore = decoded.count == self.pageSize
        }
        self.isLoading = false
      }
    }.resume()
  }
}
@MainActor
final class ArtistDetailViewModel: ObservableObject {
  @Published var artist: Artist?
  @Published var isLoading = false
  private var loadedID: String?
  func load(id: String, fallback: Artist?) {
    if loadedID == id, artist?.songListDTOs?.isEmpty == false { return }
    if artist == nil { artist = fallback }
    loadedID = id
    guard let url = URL(string: "https://api.neurokaraoke.com/api/artist/\(id)") else { return }
    isLoading = true
    var request = URLRequest(url: url)
    request.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor in
        guard let self = self else { return }
        if let data, let decoded = try? JSONDecoder().decode(Artist.self, from: data) {
          self.artist = decoded
        }
        self.isLoading = false
      }
    }.resume()
  }
}

struct ArtistsView: View {
  @StateObject private var viewModel = ArtistsViewModel()
  var body: some View {
    Group {
      if viewModel.artists.isEmpty && viewModel.isLoading {
        LoadingIndicator(size: 64)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if viewModel.artists.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: "music.mic")
            .font(.system(size: 48))
            .foregroundColor(.secondary)
          Text("No Artists Yet")
            .font(.system(size: 18, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(viewModel.artists) { artist in
            NavigationLink(destination: ArtistDetailView(artist: artist)) {
              ArtistRow(artist: artist)
            }
            .onAppear { viewModel.loadMoreIfNeeded(current: artist) }
          }
          if viewModel.isLoading {
            HStack {
              Spacer()
              LoadingIndicator(size: 28)
                .padding(.vertical, 8)
              Spacer()
            }
            .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Artists")
    .navigationBarTitleDisplayMode(.large)
    .onAppear { viewModel.fetchInitial() }
  }
}

private struct ArtistRow: View {
  let artist: Artist
  var body: some View {
    HStack(spacing: 12) {
      ArtistAvatar(url: artist.imageURL)
        .frame(width: 52, height: 52)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(artist.name)
          .font(.system(size: 16, weight: .medium))
          .lineLimit(1)
        if let count = artist.songCount, count > 0 {
          Text("\(count) songs")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
      }
      Spacer()
    }
    .padding(.vertical, 4)
  }
}

private struct ArtistAvatar: View {
  let url: URL?
  var body: some View {
    Group {
      if let url {
        LoadingImage(url: url, cornerRadius: 0, showsLoading: false)
      } else {
        ZStack {
          Color(.systemGray5)
          Image(systemName: "music.mic")
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(.secondary)
        }
      }
    }
  }
}

struct ArtistDetailView: View {
  let artist: Artist
  @StateObject private var loader = ArtistDetailViewModel()
  @EnvironmentObject var audioManager: AudioPlayerManager
  @State private var scrollOffset: CGFloat = 0
  private var current: Artist { loader.artist ?? artist }
  private var songs: [Song] { current.songListDTOs ?? [] }
  var body: some View {
    GeometryReader { geo in
      ScrollView {
        VStack(spacing: 18) {
          parallaxHero(width: geo.size.width)
          VStack(spacing: 4) {
            Text(current.name)
              .font(.title2.bold())
              .multilineTextAlignment(.center)
            if let count = current.songCount, count > 0 {
              Text("\(count) songs")
                .font(.subheadline)
                .foregroundColor(.secondary)
            } else if !songs.isEmpty {
              Text("\(songs.count) songs")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
          }
          .padding(.horizontal)
          if !songs.isEmpty {
            actionButtons
            LazyVStack(spacing: 0) {
              ForEach(songs) { song in
                Button {
                  audioManager.play(song: song, context: songs)
                } label: {
                  SongRow(song: song, size: .regular)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PressableButtonStyle())
                Divider().padding(.leading, 76)
              }
            }
            if let summary = current.summary, !summary.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                Text("About")
                  .font(.system(size: 18, weight: .bold))
                Text(summary)
                  .font(.system(size: 14))
                  .foregroundColor(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal)
              .padding(.top, 12)
            }
          } else if loader.isLoading {
            LoadingIndicator(size: 48)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 40)
          }
        }
        .padding(.bottom, 16)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: ArtistScrollOffsetKey.self,
              value: proxy.frame(in: .named("artistScroll")).minY
            )
          }
        )
      }
      .coordinateSpace(name: "artistScroll")
      .onPreferenceChange(ArtistScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .navigationTitle(scrollOffset < -180 ? current.name : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .animation(.easeInOut(duration: 0.2), value: scrollOffset < -180)
    .onAppear { loader.load(id: artist.id, fallback: artist) }
  }
  @ViewBuilder
  private func parallaxHero(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = max(0, scrollOffset)
    let shrink = max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    let blur = min(8, max(0, -scrollOffset / 30))
    let yOffset = scrollOffset > 0 ? -scrollOffset / 2 : 0
    ArtistAvatar(url: current.imageURL)
      .frame(width: size, height: size)
      .clipShape(Circle())
      .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
      .blur(radius: blur)
      .opacity(1 - min(0.7, max(0, -scrollOffset / 250)))
      .frame(width: width)
      .offset(y: yOffset)
      .padding(.top, 12)
  }
  private var actionButtons: some View {
    HStack(spacing: 12) {
      Button {
        if let first = songs.first {
          audioManager.play(song: first, context: songs)
        }
      } label: {
        actionLabel(symbol: "play.fill", text: "Play")
      }
      .buttonStyle(PressableButtonStyle())
      Button {
        if let random = songs.randomElement() {
          audioManager.play(song: random, context: songs.shuffled())
        }
      } label: {
        actionLabel(symbol: "shuffle", text: "Shuffle")
      }
      .buttonStyle(PressableButtonStyle())
    }
    .padding(.horizontal)
  }
  private func actionLabel(symbol: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
      Text(text).fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundColor(.appAccent)
    .background(Color(.tertiarySystemFill))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct ArtistScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
