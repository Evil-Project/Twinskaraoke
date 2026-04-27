//
//  iPhonePlaylistsView.swift
//  Twinskaraoke
//
//  Created by xiaoyuan on 2026/4/26.
//
import SwiftUI

struct iPhonePlaylistsView: View {
  @StateObject var viewModel = PhonePlaylistsViewModel()
  let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
  var body: some View {
    NavigationStack {
      ScrollView {
        ZStack {
          if viewModel.isLoading {
            PlaylistsSkeletonView(cols: cols)
              .transition(.opacity)
          } else if viewModel.playlists.isEmpty {
            VStack(spacing: 16) {
              Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
              Text("No playlists yet")
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            .transition(.opacity)
          } else {
            LazyVGrid(columns: cols, spacing: 16) {
              ForEach(viewModel.playlists) { playlist in
                NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                  PlaylistGridCell(playlist: playlist)
                }
                .buttonStyle(PressableButtonStyle())
              }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.isLoading)
      }
      .navigationTitle("Your Library")
      .onAppear { viewModel.fetchPlaylists() }
    }
  }
}

struct PlaylistGridCell: View {
  let playlist: Playlist
  var body: some View {
    GeometryReader { geo in
      VStack(alignment: .leading, spacing: 6) {
        LoadingImage(url: playlist.imageURL, cornerRadius: 10)
          .frame(width: geo.size.width, height: geo.size.width)
          .clipped()
          .cornerRadius(10)
        Text(playlist.name)
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.primary)
          .lineLimit(1)
        Text("\(playlist.songCount) songs")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
    }
    .aspectRatio(0.78, contentMode: .fit)
  }
}

struct PlaylistsSkeletonView: View {
  let cols: [GridItem]
  var body: some View {
    LazyVGrid(columns: cols, spacing: 16) {
      ForEach(0..<8, id: \.self) { _ in
        GeometryReader { geo in
          VStack(alignment: .leading, spacing: 6) {
            ShimmerBox(cornerRadius: 10)
              .frame(width: geo.size.width, height: geo.size.width)
            ShimmerBox(cornerRadius: 4).frame(width: geo.size.width * 0.8, height: 14)
            ShimmerBox(cornerRadius: 4).frame(width: geo.size.width * 0.5, height: 12)
          }
        }
        .aspectRatio(0.78, contentMode: .fit)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
