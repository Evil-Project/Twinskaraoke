import SwiftUI

struct NewFeaturedRail: View {
    /// The most recent karaoke stream's setlist. The website leads with it as
    /// "Recent Setlist"; the first card plays it in order.
    let latestStream: KaraokeSetlist?
    /// The 7-day trending list. Its top song gets the second card, which
    /// queues the rest of the list after it, as the website does.
    let trending: [Song]

    /// The kicker/title/subtitle block above each card's artwork. Split out of
    /// the old flat 316 so it can scale with the text, which a fixed total
    /// could not — it clipped the subtitle at the larger accessibility sizes.
    @ScaledMetric(relativeTo: .subheadline) private var cardTextAllowance: CGFloat = 73
    @State private var availableWidth: CGFloat = 390

    /// The artwork half is measured, not assumed. Pinning it to 243 — the
    /// widest card's 420 * 0.56 — left ~40pt of dead space under every card on
    /// a phone, where the card clamps far below that.
    private var cardArtworkHeight: CGFloat {
        featureCardWidth(for: availableWidth) * NewFeatureCard.artworkWidthRatio
    }

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = featureCardWidth(for: proxy.size.width)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
                    if let latestStream, latestStream.playlist.songListDTOs?.isEmpty == false {
                        NewFeatureCard(
                            kicker: String(localized: "Latest Stream"),
                            title: latestStream.name,
                            subtitle: latestStream.countAndLength,
                            artwork: .playlist(latestStream.playlist),
                            hint: String(localized: "Plays this setlist."),
                            identifier: "New.FeatureCard.LatestStream",
                            width: cardWidth,
                            artworkSize: cardWidth * NewFeatureCard.artworkWidthRatio
                        ) {
                            SetlistCardActions.play(latestStream)
                        }
                    }
                    // The top trending song, so it is labelled like the iPad
                    // hero's trending row.
                    if let secondary = trending.first {
                        NewFeatureCard(
                            kicker: String(localized: "Trending Now"),
                            title: secondary.title,
                            subtitle: secondary.displayArtist,
                            artwork: .song(secondary),
                            hint: String(localized: "Plays this song."),
                            identifier: "New.FeatureCard.Trending",
                            width: cardWidth,
                            artworkSize: cardWidth * NewFeatureCard.artworkWidthRatio
                        ) {
                            AudioPlayerManager.shared.play(song: secondary, context: trending)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .musicShelfScrolling()
        }
        .trackingWidth(into: $availableWidth)
        .frame(height: cardArtworkHeight + AM.Spacing.s + cardTextAllowance)
    }

    private func featureCardWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth - AM.Spacing.screenMargin * 2, 300), 420)
    }
}

private struct NewFeatureCard: View {
    /// The artwork's height as a fraction of the card's width. Read by
    /// NewFeaturedRail too, so the rail's frame matches what the card draws.
    static let artworkWidthRatio: CGFloat = 0.56

    enum Artwork {
        case song(Song)
        case playlist(Playlist)
    }

    let kicker: String
    let title: String
    let subtitle: String
    let artwork: Artwork
    let hint: String
    /// Names the card's role, not its song: both cards can show the same song.
    let identifier: String
    let width: CGFloat
    let artworkSize: CGFloat
    let play: () -> Void

    var body: some View {
        Button {
            AppHaptic.selection.play()
            play()
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
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ZStack(alignment: .bottomLeading) {
                    artworkImage
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
                .frame(width: width, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.82, haptic: .selection))
        .accessibilityElement(children: .combine)
        // VoiceOver reads the kicker before the title, as they are shown.
        .accessibilityLabel("\(kicker), \(title)")
        .accessibilityValue(subtitle)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var artworkImage: some View {
        switch artwork {
        case let .song(song):
            RemoteArtworkImage(
                url: song.imageURL,
                cornerRadius: AM.Radius.card,
                contentMode: .fill,
                lowResURL: song.thumbnailURL
            )
        case let .playlist(playlist):
            PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.card)
        }
    }
}

private extension KaraokeSetlist {
    /// "15 songs · 54 min", as on the Setlists screen's latest-stream card,
    /// or just the count when the length is unknown.
    var countAndLength: String {
        let count = playlist.songCountText
        guard let seconds = totalDuration, seconds > 0 else { return count }
        let length = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return String(localized: "\(count) · \(length)")
    }
}

struct NewSongRail: View {
    /// Grows the shelf with the text size; see AM.Layout.shelfLabelAllowance.
    @ScaledMetric(relativeTo: .subheadline) private var labelAllowance: CGFloat =
        AM.Layout.shelfLabelAllowance
    @State private var availableWidth: CGFloat = 390
    let title: String
    let songs: [Song]

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
            VStack(alignment: .leading, spacing: AM.Spacing.sectionHeaderGap) {
                AMSectionHeader(
                    title,
                    destination: BrowseSongCollectionView(title: title, songs: songs)
                )
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
                    .scrollTargetLayout()
                }
                .musicShelfScrolling()
            }
        }
        .trackingWidth(into: $availableWidth)
        .frame(height: AM.Layout.mediaShelfHeight(
            tileWidth: AM.Layout.shelfTileWidth(for: availableWidth),
            labelAllowance: labelAllowance
        ))
    }
}

/// The first `rowLimit` songs as rows; See All opens all of `songs`. A row
/// plays its song with all of `songs` queued, so the songs past the preview
/// follow too.
struct NewSongListPreview: View {
    let title: String
    let songs: [Song]
    var rowLimit = 5
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin

    var body: some View {
        let rows = Array(songs.prefix(rowLimit))
        VStack(alignment: .leading, spacing: AM.Spacing.sectionHeaderGap) {
            AMSectionHeader(
                title,
                destination: BrowseSongCollectionView(title: title, songs: songs),
                horizontalPadding: horizontalPadding
            )
            LazyVStack(spacing: 0) {
                ForEach(rows) { song in
                    Button {
                        AppHaptic.selection.play()
                        AudioPlayerManager.shared.play(song: song, context: songs)
                    } label: {
                        SongRow(song: song, size: .compact)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("NewSongListPreview.\(title).\(song.id)")
                    Divider().padding(.leading, 76)
                }
            }
        }
    }
}

struct NewPlaylistRail: View {
    @Namespace private var zoomNamespace
    /// Grows the shelf with the text size; see AM.Layout.shelfLabelAllowance.
    @ScaledMetric(relativeTo: .subheadline) private var labelAllowance: CGFloat =
        AM.Layout.shelfLabelAllowance
    @State private var availableWidth: CGFloat = 390
    let title: String
    let playlists: [Playlist]

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
            VStack(alignment: .leading, spacing: AM.Spacing.sectionHeaderGap) {
                AMSectionHeader(
                    title,
                    destination: PlaylistListView(title: title, playlists: playlists)
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
                        ForEach(playlists) { playlist in
                            ZoomNavigationLink(id: playlist.id, in: zoomNamespace) {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
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
                    .scrollTargetLayout()
                }
                .musicShelfScrolling()
            }
        }
        .trackingWidth(into: $availableWidth)
        .frame(height: AM.Layout.mediaShelfHeight(
            tileWidth: AM.Layout.shelfTileWidth(for: availableWidth),
            labelAllowance: labelAllowance
        ))
    }
}
