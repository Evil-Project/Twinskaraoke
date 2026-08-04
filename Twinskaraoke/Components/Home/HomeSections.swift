import SwiftUI

struct PlaylistCarousel: View {
    @Namespace private var zoomNamespace
    let title: String
    let playlists: [Playlist]
    var isLoadingMore: Bool = false
    var onAppearItem: ((Playlist) -> Void)?
    var apiURL: ((Int, Int) -> String)?
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin
    @State private var availableWidth: CGFloat = 390

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
            VStack(alignment: .leading, spacing: AM.Spacing.s) {
                AMSectionHeader(
                    title, destination: PlaylistListView(title: title, playlists: playlists, apiURL: apiURL)
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
                        ForEach(playlists) { playlist in
                            ZoomNavigationLink(id: playlist.id, in: zoomNamespace) {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                PlaylistGridCell(playlist: playlist, width: tileWidth)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .contextMenu {
                                PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
                            } preview: {
                                PlaylistContextPreview(playlist: playlist)
                            }
                            .onAppear { onAppearItem?(playlist) }
                        }
                        if isLoadingMore {
                            ProgressView()
                                .controlSize(.regular)
                                .frame(width: 60, height: tileWidth)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
            }
            .onAppear {
                updateAvailableWidth(proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                updateAvailableWidth(width)
            }
        }
        .frame(height: AM.Layout.mediaShelfHeight(tileWidth: AM.Layout.shelfTileWidth(for: availableWidth)))
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        guard width > 0, abs(width - availableWidth) > 0.5 else { return }
        availableWidth = width
    }
}

struct HomeSongSection: View {
    let title: String
    let songs: [Song]
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin
    @State private var availableWidth: CGFloat = 390

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
            VStack(alignment: .leading, spacing: AM.Spacing.s) {
                AMSectionHeader(title, destination: BrowseSongCollectionView(title: title, songs: songs))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
                        ForEach(songs) { song in
                            MusicGridCard(
                                song: song,
                                context: songs,
                                width: tileWidth,
                                accessibilityIdentifier: "HomeSongSection.\(title).\(song.id)"
                            )
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
            }
            .onAppear {
                updateAvailableWidth(proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                updateAvailableWidth(width)
            }
        }
        .frame(height: AM.Layout.mediaShelfHeight(tileWidth: AM.Layout.shelfTileWidth(for: availableWidth)))
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        guard width > 0, abs(width - availableWidth) > 0.5 else { return }
        availableWidth = width
    }
}

struct WideSongListPanel: View {
    let title: String
    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.s) {
            NavigationLink(destination: BrowseSongCollectionView(title: title, songs: songs)) {
                HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.s) {
                    Text(title)
                        .font(AM.Font.sectionHeader)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(AM.Font.chevron)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            LazyVStack(spacing: 0) {
                ForEach(songs) { song in
                    Button {
                        AppHaptic.selection.play()
                        AudioPlayerManager.shared.play(song: song, context: songs)
                    } label: {
                        SongRow(song: song, size: .compact)
                    }
                    .buttonStyle(.plain)
                    if song.id != songs.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct LatestSingleSection: View {
    let song: Song
    let context: [Song]
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin
    @State private var showAddToPlaylist = false

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.m) {
            AMSectionHeader("Latest Single")
            Button {
                play()
            } label: {
                HStack(spacing: AM.Spacing.m) {
                    RemoteArtworkImage(
                        url: song.thumbnailURL ?? song.imageURL,
                        cornerRadius: AM.Radius.card,
                        lowResURL: song.rowImageURL
                    )
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
                        .amShadow(AM.Shadow.card)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(song.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(song.displayArtist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Label("Play Latest Release", systemImage: "play.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color.appAccent)
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 12)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous)
                        .fill(Color.appSecondaryBackground)
                )
            }
            .buttonStyle(PressableButtonStyle())
            .contextMenu {
                SongActionsMenuItems(song: song) {
                    showAddToPlaylist = true
                }
            } preview: {
                SongContextPreview(song: song)
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(song: song)
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private func play() {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: context)
    }
}
