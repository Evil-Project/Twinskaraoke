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

    var usesTwoColumnPlayer: Bool {
        containerSize.width >= 700 && contentHeight >= 560
    }

    var usesTwoColumnLyrics: Bool {
        usesTwoColumnPlayer
    }

    var horizontalPadding: CGFloat {
        if usesTwoColumnPlayer { return 0 }
        if isWidePhone { return 34 }
        return isCompactHeight ? 24 : 28
    }

    var toolbarHorizontalPadding: CGFloat {
        isCompactHeight ? 38 : 48
    }

    var artSize: CGFloat {
        if usesTwoColumnPlayer { return wideArtSize }
        let widthBound = containerSize.width - (horizontalPadding * 2)
        let heightFraction = contentHeight * (isCompactHeight ? 0.43 : 0.48)
        let maxSize: CGFloat = isWidePhone ? 390 : 360
        return min(widthBound, heightFraction, maxSize)
    }

    var wideArtSize: CGFloat {
        min(containerSize.width * 0.44, contentHeight * 0.68, 460)
    }

    var wideLyricsArtSize: CGFloat {
        let panelWidth: CGFloat = 330
        let spacing: CGFloat = 36
        let available = wideContentMaxWidth - panelWidth - spacing
        return min(wideArtSize, max(240, min(360, available)))
    }

    var wideContentMaxWidth: CGFloat {
        min(containerSize.width - 88, 980)
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

    var progressTopPadding: CGFloat {
        isCompactHeight ? 10 : 16
    }

    var controlsTopPadding: CGFloat {
        isCompactHeight ? 40 : 54
    }

    var controlsBottomSpacer: CGFloat {
        isCompactHeight ? 30 : 46
    }

    var wideControlsTopPadding: CGFloat {
        isCompactHeight ? 38 : 46
    }

    var wideControlsBottomSpacer: CGFloat {
        isCompactHeight ? 30 : 38
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
}

struct FullScreenPlayerView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @ObservedObject private var popupPresentation = PopupPresentationState.shared
    @ObservedObject private var favorites = FavoritesManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var showingQueue = false
    @State private var showLyrics = false
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
                let hdURL = easterEggImageURL ?? song.fullHDImageURL ?? audioManager.displayImageURL(for: song)
                let thumbURL = isEasterEgg ? nil : audioManager.displayImageURL(for: song)
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
            if showLyrics, !audioManager.isRadioMode, let id = newId {
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
                } else {
                    lyricsViewModel.fetch(songID: id)
                }
            }
        }
        .onChange(of: audioManager.upcomingSong?.id) { _, upcomingId in
            if showLyrics, !audioManager.isRadioMode, let id = upcomingId {
                upcomingLyricsViewModel.fetch(songID: id)
            }
        }
        .onChange(of: audioManager.isRadioMode) { _, isRadio in
            if isRadio { showLyrics = false }
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
            }
        }
    }

    @ViewBuilder
    private func musicLayout(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        if showLyrics {
            if metrics.usesTwoColumnLyrics {
                wideLyricsLayout(song: song, metrics: metrics)
            } else {
                compactMusicLayout(song: song, metrics: metrics)
            }
        } else if metrics.usesTwoColumnPlayer {
            wideMusicLayout(song: song, metrics: metrics)
        } else {
            compactMusicLayout(song: song, metrics: metrics)
        }
    }

    private func compactMusicLayout(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if showLyrics {
                    VStack(spacing: 0) {
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

    private func wideMusicLayout(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: 46) {
            VStack(alignment: .leading, spacing: 22) {
                PlayerArtworkView(song: song, size: metrics.artSize, onTap: { handleCoverArtTap(song: song) })
                    .contextMenu {
                        songActions(song: song)
                    } preview: {
                        SongContextPreview(song: song)
                    }
                titleRow(song: song, metrics: metrics, horizontalPadding: 0)
            }
            .frame(width: metrics.artSize, alignment: .leading)

            VStack(spacing: 0) {
                progressSection(song: song, metrics: metrics)
                controlsRow(metrics: metrics)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, metrics.wideControlsTopPadding)
                Spacer(minLength: metrics.wideControlsBottomSpacer)
                PlayerVolumeRow(horizontalPadding: 0)
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
                    horizontalPadding: 20
                )
            }
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: metrics.wideContentMaxWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FullScreenPlayer.layout.wide")
    }

    private func wideLyricsLayout(song: Song, metrics: PlayerLayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: 36) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                PlayerArtworkView(
                    song: song,
                    size: metrics.wideLyricsArtSize,
                    onTap: { handleCoverArtTap(song: song) }
                )
                .contextMenu {
                    songActions(song: song)
                } preview: {
                    SongContextPreview(song: song)
                }
                .padding(.bottom, 24)

                titleRow(song: song, metrics: metrics, horizontalPadding: 0)
                    .padding(.bottom, 18)
                progressSection(song: song, metrics: metrics)
                controlsRow(metrics: metrics)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, metrics.wideControlsTopPadding)
                Spacer(minLength: metrics.wideControlsBottomSpacer)
                PlayerVolumeRow(horizontalPadding: 0)
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
                    horizontalPadding: 20
                )
                Spacer(minLength: 0)
            }
            .frame(width: metrics.wideLyricsArtSize, alignment: .leading)

            VStack(spacing: 0) {
                wideLyricsHeader(song: song)
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
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .overlay(alignment: .bottomLeading) {
                lyricsTranslationButton
                    .padding(.leading, 26)
                    .padding(.bottom, 24)
            }
            .overlay(alignment: .bottomTrailing) {
                if DeviceCapability.supportsKaraoke, audioManager.aiEnabled {
                    KaraokeRightDock(showKaraokeControls: $showKaraokeControls)
                        .padding(.trailing, 26)
                        .padding(.bottom, 24)
                }
            }
            .modifier(GlassRoundedRect(cornerRadius: AM.Radius.sheet))
            .frame(minWidth: 330, maxWidth: 500, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("FullScreenPlayer.lyricsPanel")
        }
        .frame(maxWidth: metrics.wideContentMaxWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FullScreenPlayer.layout.wideLyrics")
    }

    private var dismissBar: some View {
        Button {
            AppHaptic.light.play()
            popupPresentation.isExpanded = false
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
                        url: audioManager.displayImageURL(for: song), cornerRadius: 8, contentMode: .fill
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

            Button {
                let wasFavorite = favorites.isFavorite(song.id)
                favorites.toggle(songID: song.id)
                if wasFavorite {
                    AppHaptic.selection.play()
                } else {
                    AppHaptic.success.play()
                }
            } label: {
                Image(systemName: favorites.isFavorite(song.id) ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(playerTitleIconColor(isActive: favorites.isFavorite(song.id)))
                    .frame(width: 44, height: 44)
                    .background(playerTitleButtonBackground, in: Circle())
                    .overlay(playerTitleButtonBorder)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
            .accessibilityLabel(
                favorites.isFavorite(song.id) ? "Remove from Favorites" : "Add to Favorites"
            )

            Menu {
                songActions(song: song)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.bold())
                    .foregroundStyle(playerTitleIconColor())
                    .frame(width: 44, height: 44)
                    .background(playerTitleButtonBackground, in: Circle())
                    .overlay(playerTitleButtonBorder)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .selection))
            .accessibilityLabel("More")
            .accessibilityValue(song.title)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.bottom, 10)
    }

    private func wideLyricsHeader(song: Song) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lyrics")
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("FullScreenPlayer.wideLyricsTitle")
                Text(song.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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

            Menu {
                songActions(song: song)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.bold())
                    .foregroundStyle(playerTitleIconColor())
                    .frame(width: 44, height: 44)
                    .background(playerTitleButtonBackground, in: Circle())
                    .overlay(playerTitleButtonBorder)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .selection))
            .accessibilityLabel("More")
            .accessibilityValue(song.title)
        }
        .padding(.bottom, 10)
    }

    private func titleRow(
        song: Song,
        metrics: PlayerLayoutMetrics,
        horizontalPadding: CGFloat? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(metrics.titleSize <= 20 ? .headline.bold() : AM.Font.nowPlayingTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(song.displayArtist)
                    .font(metrics.artistSize <= 15 ? .subheadline : AM.Font.nowPlayingArtist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Now playing")
            .accessibilityValue("\(song.title), \(song.displayArtist)")
            Spacer(minLength: 8)
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
                    let isFav = favorites.isFavorite(song.id)
                    if #available(iOS 17.0, *), !reduceMotion {
                        Image(systemName: isFav ? "star.fill" : "star")
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Image(systemName: isFav ? "star.fill" : "star")
                    }
                }
                .font(.title2)
                .foregroundStyle(playerTitleIconColor(isActive: favorites.isFavorite(song.id)))
                .frame(
                    width: max(metrics.titleButtonSize, 44),
                    height: max(metrics.titleButtonSize, 44)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
            .accessibilityLabel(
                favorites.isFavorite(song.id) ? "Remove from Favorites" : "Add to Favorites"
            )
            .accessibilityValue(song.title)
            .accessibilityHint("Updates favorites for the current song.")
            .background(playerTitleButtonBackground, in: Circle())
            .overlay(playerTitleButtonBorder)

            Menu {
                songActions(song: song)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.bold())
                    .foregroundStyle(playerTitleIconColor())
                    .frame(
                        width: max(metrics.titleButtonSize, 44),
                        height: max(metrics.titleButtonSize, 44)
                    )
                    .background(playerTitleButtonBackground, in: Circle())
                    .overlay(playerTitleButtonBorder)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .selection))
            .accessibilityLabel("More")
            .accessibilityValue(song.title)
        }
        .contextMenu {
            songActions(song: song)
        } preview: {
            SongContextPreview(song: song)
        }
        .padding(.horizontal, horizontalPadding ?? metrics.horizontalPadding)
    }

    private var playerTitleButtonBackground: Color {
        Color.clear
    }

    private var playerTitleButtonBorder: some View {
        Circle()
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
    }

    private func playerTitleIconColor(isActive _: Bool = false) -> Color {
        Color.primary
    }

    private func progressSection(song _: Song, metrics: PlayerLayoutMetrics) -> some View {
        PlayerProgressSection(metrics: metrics)
    }

    private struct PlayerProgressSection: View {
        let metrics: PlayerLayoutMetrics
        @EnvironmentObject private var audioManager: AudioPlayerManager
        @ObservedObject private var clock = PlaybackClock.shared
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

        private var reduceMotion: Bool {
            AppMotion.reduceMotion(
                systemReduceMotion: systemReduceMotion,
                respectPreference: respectReducedMotion
            )
        }

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
                .foregroundStyle(audioManager.isEditingProgress ? Color.primary : Color.secondary)
                .scaleEffect(audioManager.isEditingProgress ? 1.12 : 1.0, anchor: .center)
                .animation(
                    reduceMotion ? nil : AppMotion.spring(response: 0.3, dampingFraction: 0.85),
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

    private func controlsRow(metrics: PlayerLayoutMetrics) -> some View {
        HStack(spacing: 0) {
            Button {
                audioManager.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: metrics.sideControlSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.transportControlHeight)
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
                .font(.system(size: metrics.primaryControlSize, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.transportControlHeight)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .medium))
            .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
            .accessibilityValue(audioManager.currentSong?.title ?? "Current song")
            Button {
                audioManager.playNextOrRandom()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: metrics.sideControlSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.transportControlHeight)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .light))
            .accessibilityLabel("Next track")
            .accessibilityHint("Skips to the next song.")
        }
    }

    private func backgroundView(song: Song) -> some View {
        PlayerAmbientBackground(
            artworkURL: audioManager.displayImageURL(for: song),
            isPlaying: audioManager.isPlaying
        )
        .id(song.id)
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
        reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0.08)
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

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
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
                    .foregroundStyle(showTranslatedLyrics ? Color.appAccent : Color.primary.opacity(0.85))
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
            reduceMotion ? nil : AppMotion.spring(response: 0.32, dampingFraction: 0.86),
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
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                #if canImport(UIKit)
                    if let data, let image = UIImage(data: data) {
                        ImageSaver.shared.save(image: image) { result in
                            DispatchQueue.main.async {
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
                coverArtSaveStatus = .failed(error?.localizedDescription ?? "Couldn't save")
                resetCoverArtSaveStatusLater()
            }
        }.resume()
    }

    private func resetCoverArtSaveStatusLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            coverArtSaveStatus = .idle
        }
    }

    private func handleCoverArtTap(song _: Song) {
        guard DeveloperMode.shouldTriggerEasterEgg() else {
            showCoverArt = true
            return
        }
        let urlString = "\(StorageHost.api)/public/art/yuri/random"
        guard let apiURL = URL(string: urlString) else {
            showCoverArt = true
            return
        }
        var request = URLRequest(url: apiURL)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let item = try? JSONDecoder().decode(RandomYuriArtItem.self, from: data),
                      let imageURL = URL(string: "\(item.url)/quality=95")
                else {
                    showCoverArt = true
                    return
                }
                easterEggImageURL = imageURL
                easterEggArtistName = item.artistCredit
                easterEggArtistLink = nil
                showCoverArt = true
            }
        }.resume()
    }

    private func fetchCoverArtArtist(songID: String) {
        if let song = audioManager.currentSong, song.fallbackArtCredit != nil {
            let fallback = FallbackArtProvider.shared.art(for: song.id)
            coverArtArtistName = fallback?.artistName
            coverArtArtistLink = fallback?.artistLink
            return
        }
        guard let url = URL(string: "\(StorageHost.api)/api/songs/\(songID)") else { return }
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let coverArt = json["coverArt"] as? [String: Any],
                  let artist = coverArt["artist"] as? [String: Any]
            else { return }
            DispatchQueue.main.async {
                coverArtArtistName = artist["name"] as? String
                coverArtArtistLink = artist["socialLink"] as? String
            }
        }.resume()
    }
}

private struct RandomYuriArtItem: Decodable {
    let url: String
    let artistCredit: String?
}
