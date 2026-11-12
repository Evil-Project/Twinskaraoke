import SwiftUI

struct NewFeaturedRail: View {
    /// The most recent karaoke stream's setlist, when it has songs. The
    /// website leads with it as "Recent Setlist". The first card opens it,
    /// and the card's play button plays it in order.
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
                    if let latestStream {
                        NewFeatureCard(
                            kicker: String(localized: "Latest Stream"),
                            title: latestStream.name,
                            subtitle: latestStream.countAndLength,
                            artwork: .playlist(latestStream.playlist),
                            hint: String(localized: "Plays this setlist."),
                            identifier: "New.FeatureCard.LatestStream",
                            width: cardWidth,
                            artworkSize: cardWidth * NewFeatureCard.artworkWidthRatio,
                            action: .open(latestStream.playlist, play: { SetlistCardActions.play(latestStream) })
                        )
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
                            artworkSize: cardWidth * NewFeatureCard.artworkWidthRatio,
                            action: .play { AudioPlayerManager.shared.play(song: secondary, context: trending) }
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .musicShelfScrolling()
        }
        .trackingWidth(into: $availableWidth)
        .frame(height: cardArtworkHeight + AM.Spacing.s + cardTextAllowance)
    }

    /// Narrow enough that the next card peeks in at the trailing edge, so the
    /// rail reads as scrollable. With both margins taken off, the second card
    /// started right at a phone's edge and looked missing.
    private func featureCardWidth(for availableWidth: CGFloat) -> CGFloat {
        let peekingWidth = availableWidth - AM.Spacing.screenMargin - AM.Spacing.l - AM.Spacing.xxl
        return min(max(peekingWidth, 300), 420)
    }
}

struct NewFeatureCard: View {
    /// The artwork's height as a fraction of the card's width. Read by
    /// NewFeaturedRail too, so the rail's frame matches what the card draws.
    static let artworkWidthRatio: CGFloat = 0.56

    enum Artwork {
        case song(Song)
        case playlist(Playlist)
    }

    /// What a tap on the card does.
    enum Action {
        /// Plays; the play glyph is part of the card.
        case play(() -> Void)
        /// Opens the playlist. The play glyph is then its own button.
        case open(Playlist, play: () -> Void)

        /// The haptic the card's button style plays on touch-down. A card
        /// that plays has none: its action plays one, and both together
        /// tapped twice for a single touch.
        var styleHaptic: AppHaptic? {
            switch self {
            case .play: nil
            case .open: .selection
            }
        }
    }

    let kicker: String
    let title: String
    let subtitle: String
    let artwork: Artwork
    /// VoiceOver's hint for whatever plays: the card, or its play button.
    let hint: String
    /// Names the card's role, not its song: both cards can show the same song.
    let identifier: String
    let width: CGFloat
    let artworkSize: CGFloat
    let action: Action
    @Namespace private var zoomNamespace

    var body: some View {
        switch action {
        case let .play(play):
            Button {
                AppHaptic.selection.play()
                play()
            } label: {
                content(showsPlayGlyph: true)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.82, haptic: action.styleHaptic))
            .accessibilityElement(children: .combine)
            // VoiceOver reads the kicker before the title, as they are shown.
            .accessibilityLabel("\(kicker), \(title)")
            .accessibilityValue(subtitle)
            .accessibilityHint(hint)
            .accessibilityIdentifier(identifier)
        case let .open(playlist, play):
            ZoomNavigationLink(id: identifier, in: zoomNamespace) {
                PlaylistDetailView(playlist: playlist)
            } label: {
                content(showsPlayGlyph: false)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.82, haptic: action.styleHaptic))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(kicker), \(title)")
            .accessibilityValue(subtitle)
            .accessibilityIdentifier(identifier)
            // Over the link, not inside its label, so a tap here plays
            // without opening the playlist.
            .overlay(alignment: .bottomLeading) {
                Button {
                    AppHaptic.selection.play()
                    play()
                } label: {
                    playGlyph
                }
                .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.8))
                .padding(10)
                .accessibilityLabel(String(localized: "Play"))
                .accessibilityHint(hint)
                .accessibilityIdentifier("\(identifier).Play")
            }
        }
    }

    private func content(showsPlayGlyph: Bool) -> some View {
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
                if showsPlayGlyph {
                    playGlyph
                        .padding(10)
                }
            }
            .frame(width: width, height: artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        }
        .frame(width: width, alignment: .leading)
    }

    private var playGlyph: some View {
        Image(systemName: "play.fill")
            .font(.headline.bold())
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.32), in: Circle())
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var labelAllowance: CGFloat =
        AM.Layout.shelfLabelAllowance
    @State private var availableWidth: CGFloat = 390
    let title: String
    let songs: [Song]

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width, accessibilityText: dynamicTypeSize.isAccessibilitySize)
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
            tileWidth: AM.Layout.shelfTileWidth(for: availableWidth, accessibilityText: dynamicTypeSize.isAccessibilitySize),
            labelAllowance: labelAllowance,
            accessibilityText: dynamicTypeSize.isAccessibilitySize
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var labelAllowance: CGFloat =
        AM.Layout.shelfLabelAllowance
    @State private var availableWidth: CGFloat = 390
    let title: String
    let playlists: [Playlist]

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width, accessibilityText: dynamicTypeSize.isAccessibilitySize)
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
            tileWidth: AM.Layout.shelfTileWidth(for: availableWidth, accessibilityText: dynamicTypeSize.isAccessibilitySize),
            labelAllowance: labelAllowance,
            accessibilityText: dynamicTypeSize.isAccessibilitySize,
            twoLineTitles: true
        ))
    }
}
