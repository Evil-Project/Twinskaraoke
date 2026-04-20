//
//  MusicGridView.swift
//  Twinskaraoke
//
//  Created by xiaoyuan on 2026/4/19.
//

import Combine
import Foundation
import SwiftUI

struct Playlist: Codable, Identifiable {
  let id: String
  let name: String
  let songCount: Int
  let mosaicMedia: [Media]?
  var imageURL: URL? {
    guard let path = mosaicMedia?.first?.absolutePath else { return nil }
    return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
  }
}

struct Media: Codable {
  let absolutePath: String
}

class MusicViewModel: ObservableObject {
  @Published var playlists: [Playlist] = []
  @Published var isLoading = false
  func fetchMusic() {
    guard
      let url = URL(
        string:
          "https://api.neurokaraoke.com/api/playlists?startIndex=0&pageSize=25&search=&sortBy=&sortDescending=False&isSetlist=True&year=0"
      )
    else { return }
    isLoading = true
    var request = URLRequest(url: url)
    request.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { data, response, error in
      if let data = data {
        if let decodedData = try? JSONDecoder().decode([Playlist].self, from: data) {
          DispatchQueue.main.async {
            self.playlists = decodedData
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

struct MusicGridView: View {
  @StateObject var viewModel = MusicViewModel()
  let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]
  var body: some View {
    NavigationStack {
      ScrollView {
        if viewModel.isLoading && viewModel.playlists.isEmpty {
          ProgressView("Loading...")
        } else {
          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.playlists) { playlist in
              NavigationLink(
                destination: MusicListView(playlistID: playlist.id, playlistName: playlist.name)
              ) {
                VStack(spacing: 8) {
                  AsyncImage(url: playlist.imageURL) { image in
                    image.resizable().scaledToFill()
                  } placeholder: {
                    Color.gray.opacity(0.2)
                  }
                  .frame(width: 60, height: 60)
                  .cornerRadius(8)
                  VStack(spacing: 2) {
                    Text(playlist.name)
                      .font(.system(size: 14, weight: .bold))
                      .foregroundColor(.primary)
                      .multilineTextAlignment(.center)
                      .lineLimit(2)
                    Text("\(playlist.songCount) songs")
                      .font(.system(size: 11))
                      .foregroundColor(.secondary)
                      .lineLimit(1)
                  }
                  .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
              }
              .buttonStyle(PlainButtonStyle())
            }
          }
          .padding()
        }
      }
      .navigationTitle("Playlists")
      .onAppear {
        viewModel.fetchMusic()
      }
    }
  }
}
