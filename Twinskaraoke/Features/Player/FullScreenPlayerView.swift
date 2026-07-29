import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

private struct PlayerLayoutMetrics {
    let containerSize: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat

    private var contentHeight: CGFloat {
        max(1, containerSize.height - safeTop - safeBottom)
    }

    private var isCompactHeight: Bool {
        contentHeight < 760
    }

    private var isWidePhone: Bool {
        containerSize.width >= 420
    }

    private var isRoomy: Bool {
        contentHeight >= 1000
    }

    /// iPad-class canvas. Slide Over and half-width Split View stay on the
    /// compact phone layout, which reads better at those widths.
    var usesPadLayout: Bool {
        containerSize.width >= 600 && contentHeight >= 600
    }

    /// Landscape iPad: lyrics fill the top, transport spans a bar along the
    /// bottom. Portrait instead keeps artwork and transport in a left rail.
    var padUsesBottomBar: Bool {
        usesPadLayout
            && containerSize.width >= 900
            && containerSize.width > contentHeight * 1.15
    }

    var horizontalPadding: CGFloat {
        if usesPadLayout { return 0 }
        if isWidePhone { return 34 }
        return isCompactHeight ? 24 : 28
    }

    var toolbarHorizontalPadding: CGFloat {
        isCompactHeight ? 38 : 48
    }

    var artSize: CGFloat {
        let widthBound = containerSize.width - (horizontalPadding * 2)
        let heightFraction = contentHeight * (isCompactHeight ? 0.43 : 0.48)
        let maxSize: CGFloat = isWidePhone ? 390 : 360
        return min(widthBound, heightFraction, maxSize)
    }

    // MARK: - iPad geometry

    var padOuterPadding: CGFloat {
        if containerSize.width >= 1180 { return 44 }
        if containerSize.width >= 860 { return 34 }
        return 26
    }

    var padColumnSpacing: CGFloat {
        containerSize.width >= 1000 ? 34 : 26
    }

    /// Keeps the layout from stretching edge to edge on a 13" canvas.
    var padContentMaxWidth: CGFloat {
        padUsesBottomBar ? 1160 : 1120
    }

    /// Lyric lines are short, so a full-width panel would strand a lot of empty
    /// space to the right of the text in landscape.
    var padLyricsPanelMaxWidth: CGFloat {
        padUsesBottomBar ? 880 : .infinity
    }

    var padRailWidth: CGFloat {
        min(max(containerSize.width * 0.40, 296), 400)
    }

    var padRailArtSize: CGFloat {
        min(padRailWidth, contentHeight * 0.34, 360)
    }

    /// Lyrics-off layout: artwork carries the screen, transport sits below it.
    var padArtworkSize: CGFloat {
        min(containerSize.width * 0.5, contentHeight * 0.44, 460)
    }

    var padArtworkContentMaxWidth: CGFloat {
        560
    }

    /// Clears the drag handle pinned to the top of the player.
    var padTopInset: CGFloat {
        26
    }

    var padTransportTopPadding: CGFloat {
        isRoomy ? 26 : 20
    }

    var padVolumeTopPadding: CGFloat {
        isRoomy ? 24 : 18
    }

    var padPanelHeaderPadding: CGFloat {
        containerSize.width >= 860 ? 22 : 18
    }

    var padBarArtSize: CGFloat {
        64
    }

    var padBarTransportMaxWidth: CGFloat {
        300
    }

    var radioArtSize: CGFloat {
        min(containerSize.width - 44, contentHeight * 0.50, isWidePhone ? 390 : 360)
    }

    var artworkTopSpacer: CGFloat {
        isCompactHeight ? 10 : 20
    }

    var artworkBottomSpacer: CGFloat {
        isCompactHeight ? 18 : 28
    }

    var lyricsTopSpacer: CGFloat {
        isCompactHeight ? 8 : 12
    }

    var lyricsBottomSpacer: CGFloat {
        isCompactHeight ? 10 : 12
    }

    var progressTopPadding: CGFloat {
        isCompactHeight ? 10 : 16
    }

    var controlsTopPadding: CGFloat {
        isCompactHeight ? 40 : 54
    }

    var controlsBottomSpacer: CGFloat {
        isCompactHeight ? 30 : 46
    }

    var transportControlHeight: CGFloat {
        isCompactHeight ? 58 : 62
    }

    var titleSize: CGFloat {
        isCompactHeight ? 20 : 22
    }

    var artistSize: CGFloat {
        isCompactHeight ? 15 : 17
    }

    var titleButtonSize: CGFloat {
        isCompactHeight ? 34 : 36
    }

    var moreButtonIconSize: CGFloat {
        isCompactHeight ? 18 : 20
    }

    var sideControlSize: CGFloat {
        isCompactHeight ? 40 : 42
    }

    var primaryControlSize: CGFloat {
        isCompactHeight ? 52 : 56
    }

    var lyricsArtworkSize: CGFloat {
        isCompactHeight ? 48 : 52
    }

    var lyricsTitleSize: CGFloat {
        isCompactHeight ? 15 : 16
    }

    var lyricsSubtitleSize: CGFloat {
        isCompactHeight ? 12 : 13
    }

    /// A `GeometryReader` reports a zero size before the first layout pass;
    /// layout decisions that stick (the initial player surface) wait for this.
    var hasResolvedGeometry: Bool {
        containerSize.width > 0 && containerSize.height > 0
    }
}

private let playerTitleButtonBackground = Color.clear

private var playerTitleButtonBorder: some View {
    Circle()
        .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
}

private func playerTitleIconColor(isActive _: Bool = false) -> Color {
    Color.primary
}

private extension View {
    /// The circular background/border worn by the player's title-surface
    /// buttons. The iPad control bar sits on its own glass and skips it.
    @ViewBuilder
    func playerTitleButtonChrome(_ isVisible: Bool) -> some View {
        if isVisible {
            background(playerTitleButtonBackground, in: Circle())
                .overlay(playerTitleButtonBorder)
        } else {
            self
        }
    }
}

/// The favorite toggle shared by the player's three title surfaces: the compact
/// title row, the compact lyrics header and the iPad landscape control bar.
/// They differ only in metrics and chrome, so the toggle, haptics, symbol
/// effect and accessibility live here rather than in triplicate.
private struct PlayerFavoriteButton: View {
    let song: Song
    var font: Font = .title3
    var size: CGFloat = 44
    var showsChrome: Bool = true

    @ObservedObject private var favorites = FavoritesManager.shared
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        let isFavorite = favorites.isFavorite(song.id)
        Button {
            let wasFavorite = favorites.isFavorite(song.id)
            favorites.toggle(songID: song.id)
            if wasFavorite {
                AppHaptic.selection.play()
            } else {
                AppHaptic.success.play()
            }
        } label: {
            Group {
                if #available(iOS 17.0, *), !reduceMotion {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isFavorite)
                } else {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
            }
            .font(font)
            .foregroundStyle(playerTitleIconColor(isActive: isFavorite))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .playerTitleButtonChrome(showsChrome)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityValue(song.title)
        .accessibilityHint("Updates favorites for the current song.")
    }
}

/// The overflow menu paired with ``PlayerFavoriteButton`` on the same three
/// surfaces.
private struct PlayerMoreMenu: View {
    let song: Song
    var font: Font = .headline.bold()
    var size: CGFloat = 44
    var showsChrome: Bool = true
    let onAddToPlaylist: () -> Void

    var body: some View {
        Menu {
            SongActionsMenuItems(song: song, onAddToPlaylist: onAddToPlaylist)
        } label: {
            Image(systemName: "ellipsis")
                .font(font)
                .foregroundStyle(playerTitleIconColor())
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .playerTitleButtonChrome(showsChrome)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .selection))
        .accessibilityLabel("More")
        .accessibilityValue(song.title)
    }
}

struct FullScreenPlayerView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @ObservedObject private var popupPresentation = PopupPresentationState.shared
    @ObservedObject private var favorites = FavoritesManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var showingQueue = false
    @State private var showLyrics = false
    @State private var didSetInitialSurface = false
    @State private var usesPadCanvas = false
    @State private var showKaraokeControls = false
    @State private var showTranslatedLyrics = false
    @State private var showCoverArt = false
    @State private var showAddToPlaylist = false
    @State private var coverArtSaveStatus: ArtworkSaveStatus = .idle
    @State private var easterEggImageURL: URL?
    @State private var easterEggArtistName: String?
    @State private var easterEggArtistLink: String?
    @State private var coverArtArtistName: String?
    @State private var coverArtArtistLink: String?
    @StateObject private var lyricsViewModel = LyricsViewModel()
    @StateObject private var upcomingLyricsViewModel = LyricsViewModel()

    var body: some View {
        let song = audioManager.currentSong
        Group {
            if let song {
                GeometryReader { geo in
                    let safeTop = geo.safeAreaInsets.top
                    let safeBottom = geo.safeAreaInsets.bottom
                    let metrics = PlayerLayoutMetrics(
                        containerSize: geo.size,
                        safeTop: safeTop,
                        safeBottom: safeBottom
                    )
                    ZStack(alignment: .top) {
                        Group {
                            if audioManager.isRadioMode {
                                RadioPlayerLayout(
                                    favorites: favorites,
                                    showingQueue: $showingQueue,
                                    song: song,
                                    artSize: metrics.radioArtSize
                                )
                            } else {
                                musicLayout(song: song, metrics: metrics)
                            }
                        }
                        .padding(.top, safeTop + 6)
                        .padding(.bottom, max(0, safeBottom - 8))
                        dismissBar
                            .padding(.top, 6)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .background(backgroundView(song: song))
                .accessibilityIdentifier("FullScreenPlayer")
            }
        }
        .fullScreenCover(isPresented: $showCoverArt) {
            if let song {
                let isEasterEgg = easterEggImageURL != nil
                let hdURL = easterEggImageURL ?? audioManager.displayImageURL(for: song, variant: .fullHD) ?? song.fullHDImageURL
                let thumbURL = isEasterEgg ? nil : audioManager.displayImageURL(for: song, variant: .thumbnail)
                ZoomableImageViewer(
                    url: hdURL,
                    lowResURL: thumbURL,
                    saveStatus: $coverArtSaveStatus,
                    onSave: { saveCoverArt(url: hdURL) },
                    title: isEasterEgg ? easterEggArtistName : coverArtArtistName,
                    subtitle: isEasterEgg ? easterEggArtistLink : coverArtArtistLink
                )
                .onDisappear {
                    easterEggImageURL = nil
                    easterEggArtistName = nil
                    easterEggArtistLink = nil
                    coverArtSaveStatus = .idle
                }
            }
        }
        .sheet(isPresented: $showingQueue) {
            Group {
                if audioManager.isRadioMode {
                    RadioQueueView()
                        .environmentObject(audioManager)
                } else {
                    QueueView()
                        .environmentObject(audioManager)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let song {
                AddToPlaylistSheet(song: song)
            }
        }
        .onChange(of: audioManager.currentSong?.id) { _, newId in
            showTranslatedLyrics = false
            showKaraokeControls = false
            showAddToPlaylist = false
            coverArtArtistName = nil
            coverArtArtistLink = nil
            if let id = newId {
                fetchCoverArtArtist(songID: id)
            }
            if !audioManager.isRadioMode, let id = newId {
                if upcomingLyricsViewModel.loadedSongID == id,
                   !upcomingLyricsViewModel.didFail,
                   !upcomingLyricsViewModel.isLoading,
                   !upcomingLyricsViewModel.lyrics.isEmpty || upcomingLyricsViewModel.hasNoLyrics
                {
                    lyricsViewModel.adopt(
                        songID: id,
                        lyrics: upcomingLyricsViewModel.lyrics,
                        hasNoLyrics: upcomingLyricsViewModel.hasNoLyrics
                    )
                } else if upcomingLyricsViewModel.isLoading {
                    // Prefetch for this song may still be in flight; the
                    // isLoading handoff below adopts it (or fetches on
                    // failure) instead of firing a duplicate GET.
                } else {
                    lyricsViewModel.fetch(songID: id)
                }
            }
        }
        .onChange(of: upcomingLyricsViewModel.isLoading) { _, isLoading in
            // Hand off an in-flight prefetch that just settled: adopt it when
            // it landed for the current song, otherwise fetch fresh.
            guard !isLoading, !audioManager.isRadioMode,
                  let id = audioManager.currentSong?.id,
                  lyricsViewModel.loadedSongID != id
            else { return }
            if upcomingLyricsViewModel.loadedSongID == id,
               !upcomingLyricsViewModel.didFail,
               !upcomingLyricsViewModel.lyrics.isEmpty || upcomingLyricsViewModel.hasNoLyrics
            {
                lyricsViewModel.adopt(
                    songID: id,
                    lyrics: upcomingLyricsViewModel.lyrics,
                    hasNoLyrics: upcomingLyricsViewModel.hasNoLyrics
                )
            } else {
                lyricsViewModel.fetch(songID: id)
            }
        }
        .onChange(of: audioManager.upcomingSong?.id) { _, upcomingId in
            if !audioManager.isRadioMode, let id = upcomingId {
                upcomingLyricsViewModel.fetch(songID: id)
            }
        }
        .onChange(of: audioManager.isRadioMode) { _, isRadio in
            // Radio has no lyrics; leaving it restores the canvas default.
            showLyrics = isRadio ? false : usesPadCanvas
        }
        .onChange(of: popupPresentation.isExpanded) { _, isShown in
            if !isShown { dismiss() }
        }
        .onChange(of: audioManager.aiEnabled) { _, enabled in
            if !enabled {
                showKaraokeControls = false
            }
        }
        .onAppear {
            favorites.loadIfNeeded()
            if let id = audioManager.currentSong?.id {
                fetchCoverArtArtist(songID: id)
                if !audioManager.isRadioMode {
                    lyricsViewModel.fetch(songID: id)
                }
            }
        }
    }

    @ViewBuilder
    private func musicLayout(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        Group {
            if metrics.usesPadLayout {
                if showLyrics {
                    padLyricsLayout(song: song, metrics: metrics)
                } else {
                    padArtworkLayout(song: song, metrics: metrics)
                }
            } else {
                compactMusicLayout(song: song, metrics: metrics)
            }
        }
        .onAppear { syncSurfaceToCanvas(metrics: metrics) }
        .onChange(of: metrics.containerSize) { _, _ in
            syncSurfaceToCanvas(metrics: metrics)
        }
    }

    /// An iPad-class canvas opens straight into live lyrics — there is room for
    /// them alongside the artwork, so the artwork-only view isn't the useful
    /// default there. This is a canvas decision, not a device one: a Slide Over
    /// or half-width Split View window runs the compact layout and should land
    /// on artwork. Geometry is only known once the player has laid out, so the
    /// initial surface is applied here rather than seeded from the device idiom.
    private func syncSurfaceToCanvas(metrics: PlayerLayoutMetrics) {
        guard metrics.hasResolvedGeometry else { return }
        // Kept in sync so leaving radio mode can restore the canvas default.
        if usesPadCanvas != metrics.usesPadLayout {
            usesPadCanvas = metrics.usesPadLayout
        }
        guard !didSetInitialSurface else { return }
        didSetInitialSurface = true
        showLyrics = metrics.usesPadLayout
    }

    private func compactMusicLayout(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if showLyrics {
                    VStack(spacing: 0) {
                        Spacer(minLength: metrics.lyricsTopSpacer)
                        lyricsHeader(song: song, metrics: metrics)
                        TimedLyricsView(
                            lyrics: lyricsViewModel.lyrics,
                            showTranslations: showTranslatedLyrics,
                            isLoading: lyricsViewModel.isLoading,
                            didFail: lyricsViewModel.didFail,
                            hasNoLyrics: lyricsViewModel.hasNoLyrics,
                            onSeek: { time in
                                let duration = audioManager.playbackDuration
                                guard duration > 0 else { return }
                                audioManager.seek(to: (time + 0.1) / duration)
                            },
                            onRetry: { lyricsViewModel.retry() }
                        )
                        Spacer(minLength: metrics.lyricsBottomSpacer)
                    }
                    .overlay(alignment: .bottomLeading) {
                        lyricsTranslationButton
                            .padding(.leading, 16)
                            .padding(.bottom, 32)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if DeviceCapability.supportsKaraoke, audioManager.aiEnabled {
                            KaraokeRightDock(showKaraokeControls: $showKaraokeControls)
                                .padding(.trailing, 16)
                                .padding(.bottom, 32)
                        }
                    }
                    .transition(lyricsSurfaceTransition)
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: metrics.artworkTopSpacer)
                        PlayerArtworkView(song: song, size: metrics.artSize, onTap: { handleCoverArtTap(song: song) })
                            .contextMenu {
                                songActions(song: song)
                            } preview: {
                                SongContextPreview(song: song)
                            }
                        Spacer(minLength: metrics.artworkBottomSpacer)
                        titleRow(song: song, metrics: metrics)
                    }
                    .transition(artworkSurfaceTransition)
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()
            .animation(playerSurfaceAnimation, value: showLyrics)
            progressSection(song: song, metrics: metrics)
            controlsRow(metrics: metrics)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.controlsTopPadding)
            Spacer(minLength: metrics.controlsBottomSpacer)
            PlayerVolumeRow(horizontalPadding: metrics.horizontalPadding)
            PlayerBottomToolbar(
                showingQueue: $showingQueue,
                song: song,
                onLyricsToggle: {
                    withOptionalAnimation(playerSurfaceAnimation) {
                        showLyrics.toggle()
                    }
                    if showLyrics { lyricsViewModel.fetch(songID: song.id) }
                },
                showLyrics: showLyrics,
                horizontalPadding: metrics.toolbarHorizontalPadding
            )
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(showLyrics ? "FullScreenPlayer.layout.compactLyrics" : "FullScreenPlayer.layout.compact")
    }

    /// Lyrics-first iPad player. Portrait keeps artwork and transport together
    /// in a left rail with lyrics beside them; landscape hands the top of the
    /// canvas to the lyrics and spreads the transport along the bottom.
    private func padLyricsLayout(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        Group {
            if metrics.padUsesBottomBar {
                VStack(spacing: metrics.padColumnSpacing) {
                    padLyricsPanel(song: song, metrics: metrics)
                    padControlBar(song: song, metrics: metrics)
                }
            } else {
                HStack(alignment: .top, spacing: metrics.padColumnSpacing) {
                    padSideRail(song: song, metrics: metrics)
                        .frame(width: metrics.padRailWidth)
                    padLyricsPanel(song: song, metrics: metrics)
                }
            }
        }
        .padding(.top, metrics.padTopInset)
        .frame(maxWidth: metrics.padContentMaxWidth, maxHeight: .infinity)
        .padding(.horizontal, metrics.padOuterPadding)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FullScreenPlayer.layout.wideLyrics")
    }

    /// Lyrics-off iPad player: artwork centred with the transport beneath it.
    private func padArtworkLayout(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            PlayerArtworkView(
                song: song,
                size: metrics.padArtworkSize,
                onTap: { handleCoverArtTap(song: song) }
            )
            .contextMenu {
                songActions(song: song)
            } preview: {
                SongContextPreview(song: song)
            }
            titleRow(song: song, metrics: metrics, horizontalPadding: 0)
                .padding(.top, 26)
            Spacer(minLength: 18)
            padTransportStack(song: song, metrics: metrics)
        }
        .padding(.top, metrics.padTopInset)
        .frame(maxWidth: metrics.padArtworkContentMaxWidth, maxHeight: .infinity)
        .padding(.horizontal, metrics.padOuterPadding)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FullScreenPlayer.layout.wide")
    }

    private func padSideRail(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            // The artwork floats in the space above the transport rather than
            // pinning to the top, which would strand a gap in the middle.
            Spacer(minLength: 0)
            PlayerArtworkView(
                song: song,
                size: metrics.padRailArtSize,
                onTap: { handleCoverArtTap(song: song) }
            )
            .contextMenu {
                songActions(song: song)
            } preview: {
                SongContextPreview(song: song)
            }
            titleRow(song: song, metrics: metrics, horizontalPadding: 0, compact: true)
                .padding(.top, 24)
            Spacer(minLength: 24)
            padTransportStack(song: song, metrics: metrics)
        }
        .frame(maxHeight: .infinity)
    }

    /// Progress, transport, volume and the toolbar as one bottom-anchored block.
    private func padTransportStack(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            progressSection(song: song, metrics: metrics)
            controlsRow(metrics: metrics)
                .padding(.top, metrics.padTransportTopPadding)
            PlayerVolumeRow(horizontalPadding: 0)
                .padding(.top, metrics.padVolumeTopPadding)
            padToolbar(song: song, horizontalPadding: 12)
        }
    }

    /// Landscape transport: now playing on the left, transport centred, output
    /// and volume on the right.
    private func padControlBar(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        VStack(spacing: 6) {
            progressSection(song: song, metrics: metrics)

            HStack(alignment: .center, spacing: 24) {
                padBarNowPlaying(song: song, metrics: metrics)
                    .frame(maxWidth: .infinity, alignment: .leading)

                controlsRow(metrics: metrics, compact: true)
                    .frame(width: metrics.padBarTransportMaxWidth)

                VStack(spacing: 6) {
                    // The song's own actions move into this cluster so the
                    // now playing group keeps its width for the title.
                    HStack(spacing: 0) {
                        padFavoriteButton(song: song)
                            .padding(.top, 16)
                        padToolbar(song: song, horizontalPadding: 0)
                        padMoreMenu(song: song)
                            .padding(.top, 16)
                    }
                    PlayerVolumeRow(horizontalPadding: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    private func padBarNowPlaying(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        HStack(spacing: 14) {
            PlayerArtworkView(
                song: song,
                size: metrics.padBarArtSize,
                onTap: { handleCoverArtTap(song: song) }
            )
            .frame(width: metrics.padBarArtSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .animation(reduceMotion ? nil : AppMotion.quick, value: song.id)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Now playing")
            .accessibilityValue("\(song.title), \(song.displayArtist)")
        }
        .contextMenu {
            songActions(song: song)
        } preview: {
            SongContextPreview(song: song)
        }
    }

    /// The control bar already sits on glass, so its actions drop the circular
    /// chrome the other two surfaces wear.
    private func padFavoriteButton(song: Song) -> some View {
        PlayerFavoriteButton(song: song, showsChrome: false)
    }

    private func padMoreMenu(song: Song) -> some View {
        PlayerMoreMenu(song: song, font: .title3, showsChrome: false) {
            showAddToPlaylist = true
        }
    }

    private func padToolbar(song: Song, horizontalPadding: CGFloat) -> some View {
        PlayerBottomToolbar(
            showingQueue: $showingQueue,
            song: song,
            onLyricsToggle: {
                withOptionalAnimation(playerSurfaceAnimation) {
                    showLyrics.toggle()
                }
                if showLyrics { lyricsViewModel.fetch(songID: song.id) }
            },
            showLyrics: showLyrics,
            horizontalPadding: horizontalPadding
        )
    }

    private func padLyricsPanel(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            padLyricsHeader(song: song)
                .padding(.horizontal, metrics.padPanelHeaderPadding)
                .padding(.top, 20)
                .padding(.bottom, 8)
            TimedLyricsView(
                lyrics: lyricsViewModel.lyrics,
                showTranslations: showTranslatedLyrics,
                isLoading: lyricsViewModel.isLoading,
                didFail: lyricsViewModel.didFail,
                hasNoLyrics: lyricsViewModel.hasNoLyrics,
                onSeek: { time in
                    let duration = audioManager.playbackDuration
                    guard duration > 0 else { return }
                    audioManager.seek(to: (time + 0.1) / duration)
                },
                onRetry: { lyricsViewModel.retry() }
            )
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottomLeading) {
            lyricsTranslationButton
                .padding(.leading, 22)
                .padding(.bottom, 20)
        }
        .overlay(alignment: .bottomTrailing) {
            if DeviceCapability.supportsKaraoke, audioManager.aiEnabled {
                KaraokeRightDock(showKaraokeControls: $showKaraokeControls)
                    .padding(.trailing, 22)
                    .padding(.bottom, 20)
            }
        }
        .modifier(GlassRoundedRect(cornerRadius: AM.Radius.sheet))
        .frame(maxWidth: metrics.padLyricsPanelMaxWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FullScreenPlayer.lyricsPanel")
    }

    private var dismissBar: some View {
        Button {
            AppHaptic.light.play()
            popupPresentation.collapse()
        } label: {
            Capsule()
                .fill(Color.primary.opacity(0.35))
                .frame(width: 40, height: 5)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.7, haptic: .light))
        .accessibilityLabel("Dismiss player")
        .accessibilityHint("Collapses the full-screen player.")
    }

    private func lyricsHeader(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        HStack(spacing: 12) {
            Button {
                withOptionalAnimation(playerSurfaceAnimation) {
                    showLyrics = false
                }
            } label: {
                HStack(spacing: 12) {
                    RemoteArtworkImage(
                        url: audioManager.displayImageURL(for: song, variant: .thumbnail),
                        cornerRadius: 8,
                        contentMode: .fill,
                        lowResURL: song.thumbnailURL
                    )
                    .frame(width: metrics.lyricsArtworkSize, height: metrics.lyricsArtworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .id(song.id)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(metrics.lyricsTitleSize <= 15 ? .subheadline.bold() : .headline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(song.displayArtist)
                            .font(metrics.lyricsSubtitleSize <= 12 ? .caption : .subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.7, haptic: .selection))
            .accessibilityLabel("Hide lyrics")
            .accessibilityValue("\(song.title), \(song.displayArtist)")
            .accessibilityHint("Returns to the player controls.")

            Spacer(minLength: 8)

            PlayerFavoriteButton(song: song)

            PlayerMoreMenu(song: song) {
                showAddToPlaylist = true
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.bottom, 10)
    }

    /// The song title and its actions live in the rail (portrait) or the control
    /// bar (landscape), so the panel header only labels the column.
    private func padLyricsHeader(song _: Song) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Lyrics")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .accessibilityIdentifier("FullScreenPlayer.wideLyricsTitle")

            Spacer(minLength: 8)

            Button {
                withOptionalAnimation(playerSurfaceAnimation) {
                    showLyrics = false
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline.bold())
                    .foregroundStyle(playerTitleIconColor())
                    .frame(width: 44, height: 44)
                    .background(playerTitleButtonBackground, in: Circle())
                    .overlay(playerTitleButtonBorder)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .selection))
            .accessibilityLabel("Hide lyrics")
            .accessibilityHint("Returns to the player controls.")
        }
    }

    private func titleRow(
        song: Song,
        metrics: PlayerLayoutMetrics,
        horizontalPadding: CGFloat? = nil,
        compact: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: compact ? 8 : 12) {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(song.title)
                    .font(compact || metrics.titleSize <= 20 ? .headline.bold() : AM.Font.nowPlayingTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                Text(song.displayArtist)
                    .font(compact || metrics.artistSize <= 15 ? .subheadline : AM.Font.nowPlayingArtist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .animation(reduceMotion ? nil : AppMotion.quick, value: song.id)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Now playing")
            .accessibilityValue("\(song.title), \(song.displayArtist)")
            Spacer(minLength: 8)
            PlayerFavoriteButton(
                song: song,
                font: .title2,
                size: max(metrics.titleButtonSize, 44)
            )

            PlayerMoreMenu(song: song, size: max(metrics.titleButtonSize, 44)) {
                showAddToPlaylist = true
            }
        }
        .contextMenu {
            songActions(song: song)
        } preview: {
            SongContextPreview(song: song)
        }
        .padding(.horizontal, horizontalPadding ?? metrics.horizontalPadding)
    }

    private func progressSection(song _: Song, metrics: PlayerLayoutMetrics) -> some View {
        PlayerProgressSection(metrics: metrics)
    }

    private struct PlayerProgressSection: View {
        let metrics: PlayerLayoutMetrics
        @EnvironmentObject private var audioManager: AudioPlayerManager
        @ObservedObject private var clock = PlaybackClock.shared
        @Environment(\.appReduceMotion) private var reduceMotion

        private func formattedTime(_ seconds: Double) -> String {
            let s = Int(seconds)
            return String(format: "%d:%02d", s / 60, s % 60)
        }

        var body: some View {
            let duration = max(audioManager.playbackDuration, 0)
            let elapsed = min(max(audioManager.playbackTime, 0), duration)
            VStack(spacing: 0) {
                AppleMusicProgressBar(
                    progress: $clock.progress,
                    isScrubbing: $audioManager.isEditingProgress,
                    onSeekEnd: { fraction in audioManager.seek(to: fraction) },
                    accessibilityLabel: "Playback position",
                    accessibilityValueText:
                    "\(formattedTime(elapsed)) elapsed, \(formattedTime(max(0, duration - elapsed))) remaining",
                    accessibilityHint: "Drag or swipe up and down to seek.",
                    scrubValueText: formattedTime(duration * clock.progress)
                )
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.progressTopPadding)
                HStack {
                    Text(formattedTime(elapsed))
                    Spacer()
                    Text(formattedTime(max(0, duration - elapsed)))
                }
                .font(AM.Font.timecode)
                .foregroundStyle(audioManager.isEditingProgress ? .primary : .secondary)
                .scaleEffect(audioManager.isEditingProgress ? 1.12 : 1.0, anchor: .center)
                .animation(
                    reduceMotion ? nil : AppMotion.quick,
                    value: audioManager.isEditingProgress
                )
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, 2)
            }
        }
    }

    private struct TimedLyricsView: View {
        let lyrics: [LyricLine]
        var showTranslations: Bool = false
        var isLoading: Bool = false
        var didFail: Bool = false
        var hasNoLyrics: Bool = false
        let onSeek: (TimeInterval) -> Void
        var onRetry: (() -> Void)?
        @ObservedObject private var clock = PlaybackClock.shared
        @EnvironmentObject private var audioManager: AudioPlayerManager

        var body: some View {
            LyricsView(
                lyrics: lyrics,
                currentTime: audioManager.playbackTime,
                showTranslations: showTranslations,
                isLoading: isLoading,
                didFail: didFail,
                hasNoLyrics: hasNoLyrics,
                onSeek: onSeek,
                onRetry: onRetry
            )
        }
    }

    private func controlsRow(metrics: PlayerLayoutMetrics, compact: Bool = false) -> some View {
        let sideSize = compact ? metrics.sideControlSize * 0.78 : metrics.sideControlSize
        let primarySize = compact ? metrics.primaryControlSize * 0.8 : metrics.primaryControlSize
        let rowHeight = compact ? metrics.transportControlHeight * 0.82 : metrics.transportControlHeight
        return HStack(spacing: 0) {
            Button {
                audioManager.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: sideSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .light))
            .accessibilityLabel("Previous track")
            .accessibilityHint("Skips to the previous song.")
            Button {
                audioManager.togglePlayPause()
            } label: {
                Group {
                    if #available(iOS 17.0, *), !reduceMotion {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    }
                }
                .font(.system(size: primarySize, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .medium))
            .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
            .accessibilityValue(audioManager.currentSong?.title ?? "Current song")
            Button {
                audioManager.playNextOrRandom()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: sideSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .light))
            .accessibilityLabel("Next track")
            .accessibilityHint("Skips to the next song.")
        }
    }

    private func backgroundView(song: Song) -> some View {
        PlayerAmbientBackground(
            artworkURL: audioManager.displayImageURL(for: song, variant: .blur),
            isPlaying: audioManager.isPlaying && popupPresentation.isExpanded
        )
    }

    private func formattedTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func songActions(song: Song) -> some View {
        SongActionsMenuItems(song: song) {
            showAddToPlaylist = true
        }
    }

    private var playerSurfaceAnimation: Animation? {
        reduceMotion ? nil : AppMotion.standard
    }

    private var lyricsSurfaceTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return AnyTransition.asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98, anchor: .center)),
            removal: .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98, anchor: .center))
        )
    }

    private var artworkSurfaceTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return AnyTransition.asymmetric(
            insertion: .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .center)),
            removal: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .center))
        )
    }

    private var lyricsTranslationButton: some View {
        Button {
            if lyricsViewModel.hasTranslatedLyrics {
                AppHaptic.selection.play()
                showTranslatedLyrics.toggle()
            } else {
                AppHaptic.light.play()
                lyricsViewModel.requestTranslation()
            }
        } label: {
            ZStack {
                if lyricsViewModel.translationState == .translating {
                    if reduceMotion {
                        Circle()
                            .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .padding(3)
                            .transition(.opacity)
                    } else {
                        TimelineView(
                            .animation(minimumInterval: DisplayRefreshRate.lightweightAnimationInterval)
                        ) { context in
                            Circle()
                                .trim(from: 0, to: 0.82)
                                .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(translationSpinnerDegrees(for: context.date)))
                                .padding(3)
                        }
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                    }
                }
                Image(systemName: showTranslatedLyrics ? "globe.badge.chevron.backward" : "globe")
                    .font(.headline)
                    .foregroundStyle(showTranslatedLyrics ? Color.appAccent : .secondary)
            }
            .frame(width: 44, height: 44)
            .modifier(GlassCircle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.7))
        .disabled(lyricsViewModel.isLoading || lyricsViewModel.hasNoLyrics)
        .accessibilityLabel(lyricsTranslationAccessibilityLabel)
        .accessibilityValue(lyricsTranslationAccessibilityValue)
        .accessibilityHint(lyricsTranslationAccessibilityHint)
        .animation(
            reduceMotion ? nil : AppMotion.quick,
            value: lyricsViewModel.translationState
        )
    }

    private func translationSpinnerDegrees(for date: Date) -> Double {
        let cycle = 1.12
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return phase * 360 - 90
    }

    private var lyricsTranslationAccessibilityLabel: String {
        if showTranslatedLyrics { return "Hide Translated Lyrics" }
        if lyricsViewModel.hasTranslatedLyrics { return "Show Translated Lyrics" }
        return "Translate Lyrics"
    }

    private var lyricsTranslationAccessibilityValue: String {
        if showTranslatedLyrics { return "On" }
        switch lyricsViewModel.translationState {
        case .idle: return "Off"
        case .translating: return "Translating"
        case .ready: return "Available"
        case .unavailable: return "Unavailable"
        case .failed: return "Failed"
        }
    }

    private var lyricsTranslationAccessibilityHint: String {
        if lyricsViewModel.hasNoLyrics { return "Lyrics are not available for this song." }
        if lyricsViewModel.hasTranslatedLyrics {
            return "Toggles translated lyrics."
        }
        return "Requests translated lyrics."
    }

    private func saveCoverArt(url: URL?) {
        guard !coverArtSaveStatus.isSaving else { return }
        guard let url else { return }
        coverArtSaveStatus = .saving
        Task {
            #if canImport(UIKit)
                if let image = await CoverArtService.fetchImage(from: url) {
                    ImageSaver.shared.save(image: image) { result in
                        Task { @MainActor in
                            switch result {
                            case .success:
                                coverArtSaveStatus = .success
                            case let .failure(err):
                                coverArtSaveStatus = .failed(err.localizedDescription)
                            }
                            resetCoverArtSaveStatusLater()
                        }
                    }
                    return
                }
            #endif
            coverArtSaveStatus = .failed("Couldn't save")
            resetCoverArtSaveStatusLater()
        }
    }

    private func resetCoverArtSaveStatusLater() {
        // A second save may start within the window; only reset if the status
        // hasn't moved on since this timer was scheduled.
        let status = coverArtSaveStatus
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if coverArtSaveStatus == status {
                coverArtSaveStatus = .idle
            }
        }
    }

    private func handleCoverArtTap(song _: Song) {
        guard DeveloperMode.shouldTriggerEasterEgg() else {
            showCoverArt = true
            return
        }
        Task {
            guard let art = await CoverArtService.fetchRandomYuriArt() else {
                showCoverArt = true
                return
            }
            easterEggImageURL = art.imageURL
            easterEggArtistName = art.artistCredit
            easterEggArtistLink = nil
            showCoverArt = true
        }
    }

    private func fetchCoverArtArtist(songID: String) {
        if let song = audioManager.currentSong, song.fallbackArtCredit != nil {
            let fallback = FallbackArtProvider.shared.art(for: song.id)
            coverArtArtistName = fallback?.artistName
            coverArtArtistLink = fallback?.artistLink
            return
        }
        Task {
            guard let credit = await CoverArtService.fetchArtistCredit(songID: songID) else { return }
            // A slow response for a previous song must not label the current one.
            guard audioManager.currentSong?.id == songID else { return }
            coverArtArtistName = credit.name
            coverArtArtistLink = credit.link
        }
    }
}
