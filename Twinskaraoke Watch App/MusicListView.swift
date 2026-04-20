//
//  MusicListView.swift
//  Twinskaraoke
//
//  Created by xiaoyuan on 2026/4/19.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

struct PlaylistDetail: Codable {
  let id: String
  let name: String
  let songListDTOs: [Song]
}

struct SongMedia: Codable {
  let absolutePath: String
}

struct Song: Codable, Identifiable, Equatable {
  let id: String
  let title: String
  let duration: Int
  let absolutePath: String
  let coverArt: SongMedia?
  let coverArtists: [String]?
  var imageURL: URL? {
    guard let path = coverArt?.absolutePath else { return nil }
    return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
  }
  var audioURL: URL? {
    let baseUrl = "https://storage.neurokaraoke.com/"
    let encodedPath =
      absolutePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? absolutePath
    return URL(string: baseUrl + encodedPath)
  }
  var artistName: String {
    coverArtists?.joined(separator: ", ") ?? "Unknown Artist"
  }
  var durationText: String {
    let minutes = duration / 60
    let seconds = duration % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  static func == (lhs: Song, rhs: Song) -> Bool {
    lhs.id == rhs.id
  }
}

class PlaylistViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var isLoading = false
  let playlistID: String
  init(playlistID: String) {
    self.playlistID = playlistID
  }
  func fetchSongs() {
    guard let url = URL(string: "https://api.neurokaraoke.com/api/playlist/\(playlistID)") else {
      return
    }
    isLoading = true
    var request = URLRequest(url: url)
    request.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { data, response, error in
      if let data = data {
        if let decodedData = try? JSONDecoder().decode(PlaylistDetail.self, from: data) {
          DispatchQueue.main.async {
            self.songs = decodedData.songListDTOs
            self.isLoading = false
          }
        } else {
          DispatchQueue.main.async {
            self.isLoading = false
          }
        }
      } else {
        DispatchQueue.main.async {
          self.isLoading = false
        }
      }
    }.resume()
  }
}

struct MusicListView: View {
  @StateObject var viewModel: PlaylistViewModel
  let playlistName: String
  init(playlistID: String, playlistName: String) {
    self.playlistName = playlistName
    _viewModel = StateObject(wrappedValue: PlaylistViewModel(playlistID: playlistID))
  }
  var body: some View {
    List {
      if viewModel.isLoading && viewModel.songs.isEmpty {
        HStack {
          Spacer()
          ProgressView("Loading...")
          Spacer()
        }
      } else {
        ForEach(viewModel.songs) { song in
          NavigationLink(
            destination: MusicPlayerView(
              songs: viewModel.songs,
              initialIndex: viewModel.songs.firstIndex(where: { $0.id == song.id }) ?? 0)
          ) {
            HStack(spacing: 10) {
              AsyncImage(url: song.imageURL) { image in
                image.resizable().scaledToFill()
              } placeholder: {
                Color.gray.opacity(0.2)
              }
              .frame(width: 40, height: 40)
              .cornerRadius(4)
              VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                  .font(.system(size: 14, weight: .medium))
                  .lineLimit(1)
                HStack {
                  Text(song.artistName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                  Spacer()
                  Text(song.durationText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
              }
            }
            .padding(.vertical, 4)
          }
        }
      }
    }
    .navigationTitle(playlistName)
    .onAppear {
      viewModel.fetchSongs()
    }
  }
}
