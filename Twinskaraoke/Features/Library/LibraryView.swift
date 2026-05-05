import SwiftUI

struct LibraryView: View {
  @StateObject var viewModel = PlaylistsViewModel()
  let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
  var body: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink {
            PlaylistsGridScreen(viewModel: viewModel)
          } label: {
            LibraryRow(icon: "music.note.list", color: .appAccent, title: "Playlists")
          }
          NavigationLink {
            ArtistsView()
          } label: {
            LibraryRow(icon: "music.mic", color: .appAccent, title: "Artists")
          }
          NavigationLink {
            LibraryPlaceholderView(title: "Albums", systemImage: "square.stack")
          } label: {
            LibraryRow(icon: "square.stack", color: .appAccent, title: "Albums")
          }
          NavigationLink {
            LibraryPlaceholderView(title: "Songs", systemImage: "music.note")
          } label: {
            LibraryRow(icon: "music.note", color: .appAccent, title: "Songs")
          }
          NavigationLink {
            LibraryPlaceholderView(title: "Made For You", systemImage: "sparkles")
          } label: {
            LibraryRow(icon: "sparkles", color: .appAccent, title: "Made For You")
          }
          NavigationLink {
            VideoGalleryView()
          } label: {
            LibraryRow(icon: "play.rectangle", color: .appAccent, title: "Video Gallery")
          }
          NavigationLink {
            ArtGalleryView()
          } label: {
            LibraryRow(icon: "paintpalette", color: .appAccent, title: "Art Gallery")
          }
          NavigationLink {
            LibraryPlaceholderView(title: "Genres", systemImage: "guitars")
          } label: {
            LibraryRow(icon: "guitars", color: .appAccent, title: "Genres")
          }
          NavigationLink {
            LibraryPlaceholderView(title: "Composers", systemImage: "music.quarternote.3")
          } label: {
            LibraryRow(icon: "music.quarternote.3", color: .appAccent, title: "Composers")
          }
          NavigationLink {
            LibraryPlaceholderView(title: "Compilations", systemImage: "rectangle.stack")
          } label: {
            LibraryRow(icon: "rectangle.stack", color: .appAccent, title: "Compilations")
          }
          NavigationLink {
            DownloadedSongsView()
          } label: {
            LibraryRow(icon: "arrow.down.circle.fill", color: .appAccent, title: "Downloaded")
          }
          NavigationLink {
            RandomSongsView()
          } label: {
            LibraryRow(icon: "shuffle", color: .appAccent, title: "Random Songs")
          }
        }
        Section {
          RecentlyAddedCarousel(viewModel: viewModel)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listSectionSpacing(.compact)
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Library")
      .onAppear {
        viewModel.fetchPlaylists()
        viewModel.fetchFavoriteSongs()
      }
    }
  }
}

private struct RecentlyAddedCarousel: View {
  @ObservedObject var viewModel: PlaylistsViewModel
  @ObservedObject var savedStore: SavedPlaylistsStore = .shared
  @ObservedObject var addedTracker: RecentlyAddedTracker = .shared
  private let rows = [
    GridItem(.fixed(220), spacing: AM.Spacing.l),
    GridItem(.fixed(220), spacing: AM.Spacing.l),
  ]
  var body: some View {
    let recents = viewModel.recentlyAddedPlaylists(saved: savedStore.playlists)
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader("Recently Added")
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHGrid(rows: rows, spacing: AM.Spacing.l) {
          ForEach(recents) { playlist in
            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
              VStack(alignment: .leading, spacing: AM.Spacing.s) {
                PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.card)
                  .frame(width: AM.Spacing.shelfTile, height: AM.Spacing.shelfTile)
                  .clipShape(
                    RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
                  .amShadow(AM.Shadow.card)
                Text(playlist.name)
                  .font(AM.Font.tileTitle)
                  .foregroundColor(.primary)
                  .lineLimit(1)
                Text("\(playlist.songCount) songs")
                  .font(AM.Font.tileCaption)
                  .foregroundColor(.secondary)
                  .lineLimit(1)
              }
              .frame(width: AM.Spacing.shelfTile)
            }
            .buttonStyle(PressableButtonStyle())
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
  }
}

struct LibraryRow: View {
  let icon: String
  let color: Color
  let title: String
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 20, weight: .medium))
        .foregroundColor(color)
        .frame(width: 28)
      Text(title)
        .font(.system(size: 17))
      Spacer()
    }
    .padding(.vertical, 4)
  }
}

struct PlaylistListRow: View {
  let playlist: Playlist
  var body: some View {
    HStack(spacing: 12) {
      PlaylistArtwork(playlist: playlist, cornerRadius: 6)
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text(playlist.name)
          .font(.system(size: 15, weight: .medium))
          .lineLimit(1)
        Text("\(playlist.songCount) songs")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
      Spacer()
    }
    .padding(.vertical, 2)
  }
}

struct PlaylistsGridScreen: View {
  @ObservedObject var viewModel: PlaylistsViewModel
  @ObservedObject var savedStore: SavedPlaylistsStore = .shared
  let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
  var body: some View {
    let all = viewModel.allPlaylists(saved: savedStore.playlists)
    ScrollView {
      Group {
        if viewModel.isLoading && all.isEmpty {
          PlaylistsSkeletonView(cols: cols)
        } else if all.isEmpty {
          VStack(spacing: 16) {
            Image(systemName: "music.note.list")
              .font(.system(size: 48))
              .foregroundColor(.secondary)
            Text("No playlists yet")
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.top, 80)
        } else {
          LazyVGrid(columns: cols, spacing: 16) {
            ForEach(all) { playlist in
              NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                PlaylistGridCell(playlist: playlist)
              }
              .buttonStyle(PressableButtonStyle())
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
      }
    }
    .navigationTitle("Playlists")
  }
}

struct PlaylistGridCell: View {
  let playlist: Playlist
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      PlaylistArtwork(playlist: playlist, cornerRadius: 10)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
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

struct LibraryPlaceholderView: View {
  let title: String
  let systemImage: String
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: systemImage)
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("No \(title) Yet")
        .font(.system(size: 18, weight: .semibold))
      Text("Items you add will appear here.")
        .font(.system(size: 14))
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct PlaylistsSkeletonView: View {
  let cols: [GridItem]
  var body: some View {
    LoadingIndicator(size: 64)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, 80)
  }
}
