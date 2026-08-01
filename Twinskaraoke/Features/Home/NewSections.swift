import SwiftUI

struct NewFeaturedRail: View {
    let primary: Song?
    let secondary: Song?
    let songs: [Song]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
                if let primary {
                    NewFeatureCard(
                        kicker: "Updated Playlist",
                        title: "New Tracks",
                        subtitle: primary.displayArtist.isEmpty ? "Twinskaraoke" : primary.displayArtist,
                        song: primary,
                        context: songs
                    )
                }
                if let secondary {
                    NewFeatureCard(
                        kicker: "Featured Release",
                        title: secondary.title,
                        subtitle: secondary.displayArtist,
                        song: secondary,
                        context: songs
                    )
                }
            }
            .padding(.horizontal, AM.Spacing.screenMargin)
        }
    }
}

private struct NewFeatureCard: View {
    let kicker: String
    let title: String
    let subtitle: String
    let song: Song
    let context: [Song]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.play(song: song, context: context)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kicker)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ZStack(alignment: .bottomLeading) {
                    RemoteArtworkImage(
                        url: song.imageURL,
                        cornerRadius: AM.Radius.card,
                        contentMode: .fill,
                        lowResURL: song.thumbnailURL
                    )
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.38)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    Image(systemName: "play.fill")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.32), in: Circle())
                        .padding(10)
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerRelativeFrame(.horizontal) { length, _ in
            min(max(length - AM.Spacing.screenMargin * 2, 300), 420)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.82, haptic: .selection))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityHint("Plays this release.")
    }
}

struct NewSongRail: View {
    let title: String
    let songs: [Song]

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
            VStack(alignment: .leading, spacing: AM.Spacing.m) {
                AMSectionHeader(title, destination: BrowseSongCollectionView(title: title, songs: songs))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
                        ForEach(songs) { song in
                            MusicGridCard(
                                song: song,
                                context: songs,
                                width: tileWidth
                            )
                        }
                    }
                    .padding(.horizontal, AM.Spacing.screenMargin)
                }
            }
        }
        .frame(height: AM.Layout.mediaShelfHeight)
    }
}

struct NewSongListPreview: View {
    let title: String
    let songs: [Song]
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.s) {
            AMSectionHeader(title, destination: BrowseSongCollectionView(title: title, songs: songs))
            LazyVStack(spacing: 0) {
                ForEach(songs) { song in
                    Button {
                        AppHaptic.selection.play()
                        AudioPlayerManager.shared.play(song: song, context: songs)
                    } label: {
                        SongRow(song: song, size: .compact)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 76)
                }
            }
        }
    }
}

struct NewPlaylistRail: View {
    let title: String
    let playlists: [Playlist]

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
            VStack(alignment: .leading, spacing: AM.Spacing.m) {
                AMSectionHeader(title, destination: PlaylistListView(title: title, playlists: playlists))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
                        ForEach(playlists) { playlist in
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                PlaylistGridCell(playlist: playlist, width: tileWidth)
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
                            .contextMenu {
                                PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
                            } preview: {
                                PlaylistContextPreview(playlist: playlist)
                            }
                        }
                    }
                    .padding(.horizontal, AM.Spacing.screenMargin)
                }
            }
        }
        .frame(height: AM.Layout.mediaShelfHeight)
    }
}
