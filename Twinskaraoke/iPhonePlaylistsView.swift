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
    VStack(alignment: .leading, spacing: 6) {
      LoadingImage(url: playlist.imageURL, cornerRadius: 10)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
      Text(playlist.name)
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(.primary)
        .lineLimit(1)
      Text("\(playlist.songCount) songs")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct PlaylistsSkeletonView: View {
  let cols: [GridItem]
  var body: some View {
    LazyVGrid(columns: cols, spacing: 16) {
      ForEach(0..<8, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 6) {
          ShimmerBox(cornerRadius: 10)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
          ShimmerBox(cornerRadius: 4)
            .frame(height: 14)
          HStack {
            ShimmerBox(cornerRadius: 4).frame(width: 80, height: 12)
            Spacer()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
