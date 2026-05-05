import SwiftUI

struct HomeView: View {
  @StateObject var viewModel = HomeViewModel()
  @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    NavigationStack {
      ScrollView {
        Group {
          if viewModel.isLoading {
            HomeSkeletonView()
              .transition(.opacity)
          } else {
            VStack(alignment: .leading, spacing: AM.Spacing.shelfSpacing) {
              if !viewModel.recentPlaylists.isEmpty {
                PlaylistCarousel(
                  title: "Top Picks",
                  playlists: viewModel.recentPlaylists,
                  isLoadingMore: viewModel.isLoadingMoreTopPicks,
                  onAppearItem: { viewModel.loadMoreTopPicksIfNeeded(current: $0) }
                )
              }
              if !recentlyPlayed.playlists.isEmpty {
                PlaylistCarousel(title: "Recently Played", playlists: recentlyPlayed.playlists)
              }
              if !viewModel.suggestions.isEmpty {
                HomeSongSection(title: "Made for You", songs: viewModel.suggestions)
              }
              HomePlaceholderSection(
                title: "New Releases",
                tiles: HomePlaceholderTile.newReleases
              )
              HomePlaceholderSection(
                title: "Stations for You",
                tiles: HomePlaceholderTile.stations,
                style: .station
              )
              if !viewModel.trending.isEmpty {
                HomeSongSection(title: "More to Explore", songs: viewModel.trending)
              }
            }
            .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.isLoading)
        .padding(.vertical)
        .padding(.bottom, AM.Spacing.l)
      }
      .navigationTitle("Home")
      .onAppear { viewModel.fetchHomeData() }
    }
  }
}

struct PlaylistCarousel: View {
  let title: String
  let playlists: [Playlist]
  var isLoadingMore: Bool = false
  var onAppearItem: ((Playlist) -> Void)? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(title, destination: PlaylistListView(title: title, playlists: playlists))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: AM.Spacing.l) {
          ForEach(playlists) { playlist in
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
            .onAppear { onAppearItem?(playlist) }
          }
          if isLoadingMore {
            LoadingIndicator(size: 32)
              .frame(width: 60, height: AM.Spacing.shelfTile)
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
  }
}

struct PlaylistListView: View {
  let title: String
  let playlists: [Playlist]
  let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
  var body: some View {
    ScrollView {
      LazyVGrid(columns: cols, spacing: AM.Spacing.l) {
        ForEach(playlists) { playlist in
          NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            PlaylistGridCell(playlist: playlist)
          }
          .buttonStyle(PressableButtonStyle())
        }
      }
      .padding(.horizontal, AM.Spacing.screenMargin)
      .padding(.vertical, AM.Spacing.m)
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct HomeSongSection: View {
  let title: String
  let songs: [Song]
  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(title, destination: BrowseSongCollectionView(title: title, songs: songs))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: AM.Spacing.l) {
          ForEach(songs) { song in
            HomeSongCard(song: song, context: songs)
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
  }
}

struct HomeSongCard: View {
  let song: Song
  let context: [Song]
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    Button {
      audioManager.play(song: song, context: context)
    } label: {
      VStack(alignment: .leading, spacing: AM.Spacing.s) {
        LoadingImage(url: song.imageURL, cornerRadius: AM.Radius.card)
          .frame(width: AM.Spacing.shelfTile, height: AM.Spacing.shelfTile)
          .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
          .amShadow(AM.Shadow.card)
        Text(song.title)
          .font(AM.Font.tileTitle)
          .foregroundColor(.primary)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(AM.Font.tileCaption)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      .frame(width: AM.Spacing.shelfTile)
    }
    .buttonStyle(PressableButtonStyle())
  }
}

struct HomePlaceholderTile: Identifiable {
  let id = UUID()
  let title: String
  let subtitle: String
  let gradient: [Color]
  static let newReleases: [HomePlaceholderTile] = [
    .init(
      title: "Latest Singles", subtitle: "Updated daily",
      gradient: [
        Color(red: 0.96, green: 0.30, blue: 0.45), Color(red: 0.55, green: 0.10, blue: 0.30),
      ]),
    .init(
      title: "New Albums", subtitle: "This week",
      gradient: [
        Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.10, green: 0.20, blue: 0.55),
      ]),
    .init(
      title: "Coming Soon", subtitle: "Pre-add now",
      gradient: [
        Color(red: 0.95, green: 0.45, blue: 0.10), Color(red: 0.55, green: 0.15, blue: 0.05),
      ]),
  ]
  static let stations: [HomePlaceholderTile] = [
    .init(
      title: "Pop Station", subtitle: "Today's biggest hits",
      gradient: [
        Color(red: 0.90, green: 0.20, blue: 0.55), Color(red: 0.40, green: 0.05, blue: 0.30),
      ]),
    .init(
      title: "Hip-Hop Station", subtitle: "Curated for you",
      gradient: [
        Color(red: 0.60, green: 0.30, blue: 0.95), Color(red: 0.20, green: 0.05, blue: 0.45),
      ]),
    .init(
      title: "Chill Station", subtitle: "Easy listening",
      gradient: [
        Color(red: 0.10, green: 0.75, blue: 0.85), Color(red: 0.05, green: 0.30, blue: 0.45),
      ]),
  ]
}

struct HomePlaceholderSection: View {
  enum Style { case card, station }
  let title: String
  let tiles: [HomePlaceholderTile]
  var style: Style = .card
  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(title)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: AM.Spacing.l) {
          ForEach(tiles) { tile in
            HomePlaceholderTileView(tile: tile, style: style)
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
  }
}

private struct HomePlaceholderTileView: View {
  let tile: HomePlaceholderTile
  let style: HomePlaceholderSection.Style
  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: tile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        if style == .station {
          Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 28, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .padding(AM.Spacing.m)
        }
      }
      .frame(width: AM.Spacing.shelfTile, height: AM.Spacing.shelfTile)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
      .amShadow(AM.Shadow.card)
      Text(tile.title)
        .font(AM.Font.tileTitle)
        .foregroundColor(.primary)
        .lineLimit(1)
      Text(tile.subtitle)
        .font(AM.Font.tileCaption)
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .frame(width: AM.Spacing.shelfTile)
  }
}

struct HomeSkeletonView: View {
  var body: some View {
    LoadingIndicator(size: 64)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, 80)
  }
}

/// A read-only, "playlist-looking" detail screen for ad-hoc song collections
/// like Home's "More to Explore". Mirrors PlaylistDetailView's hero + list
/// layout but isn't backed by a Playlist — no save, no menu, no recently-played
/// tracking.
struct BrowseSongCollectionView: View {
  let title: String
  let subtitle: String?
  let songs: [Song]
  @EnvironmentObject var audioManager: AudioPlayerManager
  @State private var scrollOffset: CGFloat = 0
  init(title: String, subtitle: String? = nil, songs: [Song]) {
    self.title = title
    self.subtitle = subtitle
    self.songs = songs
  }
  var body: some View {
    GeometryReader { geo in
      ScrollView {
        VStack(spacing: 18) {
          parallaxHero(width: geo.size.width)
          VStack(spacing: 4) {
            Text(title)
              .font(.title2.bold())
              .multilineTextAlignment(.center)
            Text(subtitle ?? "\(songs.count) songs")
              .font(.subheadline)
              .foregroundColor(.secondary)
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
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .padding(.vertical, 6)
                }
                .buttonStyle(PressableButtonStyle())
                Divider().padding(.leading, 76)
              }
            }
          }
        }
        .padding(.bottom, AM.Spacing.l)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: BrowseScrollOffsetKey.self,
              value: proxy.frame(in: .named("browseScroll")).minY
            )
          }
        )
      }
      .coordinateSpace(name: "browseScroll")
      .onPreferenceChange(BrowseScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .navigationTitle(scrollOffset < -180 ? title : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .animation(.easeInOut(duration: 0.2), value: scrollOffset < -180)
  }
  @ViewBuilder
  private func parallaxHero(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = max(0, scrollOffset)
    let shrink = max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    let yOffset = scrollOffset > 0 ? -scrollOffset / 2 : 0
    heroArtwork
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
      .amShadow(AM.Shadow.heroIdle)
      .offset(y: yOffset)
      .frame(maxWidth: .infinity)
      .frame(height: baseSize)
      .padding(.top, 8)
  }
  @ViewBuilder
  private var heroArtwork: some View {
    if let first = songs.first {
      LoadingImage(url: first.imageURL, cornerRadius: 0, contentMode: .fill)
    } else {
      Color.secondary.opacity(0.2)
    }
  }
  private var actionButtons: some View {
    HStack(spacing: AM.Spacing.m) {
      Button {
        if let first = songs.first {
          audioManager.play(song: first, context: songs)
        }
      } label: {
        Label("Play", systemImage: "play.fill")
          .font(.system(size: 17, weight: .semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(Color.primary.opacity(0.08))
          .foregroundColor(.appAccent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      Button {
        if let pick = songs.randomElement() {
          audioManager.play(song: pick, context: songs.shuffled())
        }
      } label: {
        Label("Shuffle", systemImage: "shuffle")
          .font(.system(size: 17, weight: .semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(Color.primary.opacity(0.08))
          .foregroundColor(.appAccent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .padding(.horizontal, AM.Spacing.screenMargin)
  }
}

private struct BrowseScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
