import Combine
import SwiftUI

struct iPhoneHomeView: View {
  @StateObject var viewModel = HomeViewModel()
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    NavigationStack {
      ScrollView {
        ZStack {
          if viewModel.isLoading {
            HomeSkeletonView()
              .transition(.opacity)
          } else {
            VStack(alignment: .leading, spacing: 28) {
              if let recent = viewModel.recentPlaylist {
                RecentPlaylistSection(playlist: recent)
              }
              if !viewModel.trending.isEmpty {
                HomeSongSection(title: "Trending", songs: viewModel.trending)
              }
              if !viewModel.suggestions.isEmpty {
                HomeSongSection(title: "Suggestions", songs: viewModel.suggestions)
              }
            }
            .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.isLoading)
        .padding(.vertical)
        .padding(.bottom, 16)
      }
      .navigationTitle("Home")
      .onAppear { viewModel.fetchHomeData() }
    }
  }
}

struct RecentPlaylistSection: View {
  let playlist: Playlist
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Recent Playlist")
          .font(.title2.bold())
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.pink)
      }
      .padding(.horizontal)
      NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
        VStack(spacing: 0) {
          HStack(spacing: 16) {
            LoadingImage(url: playlist.imageURL, cornerRadius: 8)
              .frame(width: 60, height: 60)
              .cornerRadius(8)
            VStack(alignment: .leading, spacing: 3) {
              Text(playlist.name)
                .font(.headline)
                .foregroundColor(.primary)
              Text("\(playlist.songCount) songs")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(.secondary)
          }
          .padding()
          if let songs = playlist.songListDTOs {
            ForEach(songs.prefix(10)) { song in
              Divider().padding(.leading, 76)
              Button {
                audioManager.play(song: song, context: songs)
              } label: {
                PlaylistRow(song: song)
              }
              .buttonStyle(PressableButtonStyle())
            }
          }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
      }
      .buttonStyle(PressableButtonStyle())
    }
  }
}

struct PlaylistRow: View {
  let song: PhoneSong
  var body: some View {
    HStack(spacing: 12) {
      LoadingImage(url: song.imageURL, cornerRadius: 4)
        .frame(width: 40, height: 40)
        .clipped()
        .cornerRadius(4)
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)
          .lineLimit(1)
        Text(song.originalArtists?.first ?? "Unknown")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
  }
}

struct PlaylistDetailView: View {
  let playlist: Playlist
  @EnvironmentObject var audioManager: AudioPlayerManager
  @StateObject private var loader = PlaylistDetailLoader()
  var body: some View {
    let songs: [PhoneSong] = loader.songs ?? playlist.songListDTOs ?? []
    ScrollView {
      VStack(spacing: 18) {
        LoadingImage(url: playlist.imageURL, cornerRadius: 14)
          .frame(width: 240, height: 240)
          .cornerRadius(14)
          .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
        VStack(spacing: 4) {
          Text(playlist.name)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
          Text("\(playlist.songCount) songs")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        if !songs.isEmpty {
          HStack(spacing: 12) {
            Button {
              if let first = songs.first {
                audioManager.play(song: first, context: songs)
              }
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "play.fill")
                Text("Play").fontWeight(.semibold)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .foregroundColor(.pink)
              .background(Color(.tertiarySystemFill))
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            Button {
              if let random = songs.randomElement() {
                audioManager.play(song: random, context: songs.shuffled())
              }
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "shuffle")
                Text("Shuffle").fontWeight(.semibold)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .foregroundColor(.pink)
              .background(Color(.tertiarySystemFill))
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
          }
          .padding(.horizontal)
          LazyVStack(spacing: 0) {
            ForEach(songs) { song in
              Button {
                audioManager.play(song: song, context: songs)
              } label: {
                PlaylistRow(song: song)
              }
              .buttonStyle(PressableButtonStyle())
              Divider().padding(.leading, 76)
            }
          }
        } else if loader.isLoading {
          VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
              HStack(spacing: 12) {
                ShimmerBox(cornerRadius: 4).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 6) {
                  ShimmerBox(cornerRadius: 4).frame(width: 160, height: 14)
                  ShimmerBox(cornerRadius: 4).frame(width: 100, height: 12)
                }
                Spacer()
              }
              .padding(.horizontal)
              .padding(.vertical, 8)
              Divider().padding(.leading, 76)
            }
          }
        }
      }
      .padding(.top, 12)
      .padding(.bottom, 16)
    }
    .navigationTitle(playlist.name)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { loader.load(playlistID: playlist.id, fallback: playlist.songListDTOs) }
  }
}

class PlaylistDetailLoader: ObservableObject {
  @Published var songs: [PhoneSong]?
  @Published var isLoading = false
  private var loadedID: String?

  func load(playlistID: String, fallback: [PhoneSong]?) {
    let alreadyFullyLoaded = (loadedID == playlistID) && (songs?.isEmpty == false)
    if alreadyFullyLoaded { return }
    loadedID = playlistID
    if (songs?.isEmpty ?? true), let fallback = fallback, !fallback.isEmpty {
      self.songs = fallback
    }
    guard
      let url = URL(string: "https://api.neurokaraoke.com/api/playlist/\(playlistID)")
    else { return }
    isLoading = true
    var r = URLRequest(url: url)
    r.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
      guard let self = self else { return }
      let list = Self.decodeSongs(from: data)
      DispatchQueue.main.async {
        if let list = list, !list.isEmpty {
          self.songs = list
        }
        self.isLoading = false
      }
    }.resume()
  }

  private static func decodeSongs(from data: Data?) -> [PhoneSong]? {
    guard let data = data else { return nil }
    let decoder = JSONDecoder()
    if let playlist = try? decoder.decode(Playlist.self, from: data),
      let list = playlist.songListDTOs, !list.isEmpty
    {
      return list
    }
    if let list = try? decoder.decode([PhoneSong].self, from: data), !list.isEmpty {
      return list
    }
    if let wrapped = try? decoder.decode(PlaylistSongsWrapper.self, from: data),
      !wrapped.songs.isEmpty
    {
      return wrapped.songs
    }
    return nil
  }
}

private struct PlaylistSongsWrapper: Codable {
  let songs: [PhoneSong]

  enum CodingKeys: String, CodingKey {
    case items, songListDTOs, songs
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let v = try? c.decode([PhoneSong].self, forKey: .songListDTOs) {
      songs = v
    } else if let v = try? c.decode([PhoneSong].self, forKey: .items) {
      songs = v
    } else if let v = try? c.decode([PhoneSong].self, forKey: .songs) {
      songs = v
    } else {
      songs = []
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(songs, forKey: .songs)
  }
}

struct HomeSongSection: View {
  let title: String
  let songs: [PhoneSong]
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.title2.bold())
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.pink)
      }
      .padding(.horizontal)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 16) {
          ForEach(songs) { song in
            Button {
              audioManager.play(song: song, context: songs)
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                LoadingImage(url: song.imageURL, cornerRadius: 12)
                  .frame(width: 140, height: 140)
                  .clipped()
                  .cornerRadius(12)
                Text(song.title)
                  .font(.system(size: 13, weight: .bold))
                  .foregroundColor(.primary)
                  .lineLimit(1)
                Text(song.originalArtists?.joined(separator: ", ") ?? "")
                  .font(.system(size: 11))
                  .foregroundColor(.secondary)
                  .lineLimit(1)
              }
              .frame(width: 140)
            }
            .buttonStyle(PressableButtonStyle())
          }
        }
        .padding(.horizontal)
      }
    }
  }
}

struct HomeSkeletonView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      VStack(alignment: .leading, spacing: 12) {
        ShimmerBox(cornerRadius: 6)
          .frame(width: 160, height: 24)
          .padding(.horizontal)
        VStack(spacing: 0) {
          HStack(spacing: 16) {
            ShimmerBox(cornerRadius: 8)
              .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 6) {
              ShimmerBox(cornerRadius: 4).frame(width: 120, height: 14)
              ShimmerBox(cornerRadius: 4).frame(width: 70, height: 12)
            }
            Spacer()
          }
          .padding()
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
      }
      ForEach(0..<2, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 12) {
          ShimmerBox(cornerRadius: 6)
            .frame(width: 130, height: 24)
            .padding(.horizontal)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
              ForEach(0..<5, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                  ShimmerBox(cornerRadius: 12)
                    .frame(width: 140, height: 140)
                  ShimmerBox(cornerRadius: 4).frame(width: 110, height: 13)
                  ShimmerBox(cornerRadius: 4).frame(width: 80, height: 11)
                }
                .frame(width: 140)
              }
            }
            .padding(.horizontal)
          }
        }
      }
    }
  }
}
