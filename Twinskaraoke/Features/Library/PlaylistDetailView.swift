import Combine
import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @StateObject private var loader = PlaylistDetailViewModel()
    @ObservedObject private var favorites = FavoritesManager.shared
    @ObservedObject private var fallbackArt = FallbackArtProvider.shared
    @State private var scrollOffset: CGFloat = 0
    private func usesWideOverview(availableWidth: CGFloat) -> Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        let songs: [Song] = loader.songs ?? playlist.songListDTOs ?? []
        GeometryReader { geo in
            ScrollView {
                playlistOverview(songs: songs, width: geo.size.width)
                    .padding(.bottom, 16)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: proxy.frame(in: .named("playlistScroll")).minY
                            )
                        }
                    )
            }
            .smoothScrolling()
            .coordinateSpace(name: "playlistScroll")
            .bottomChromeScrollTracking()
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = quantizedScrollOffset($0) }
        }
        .navigationTitle(scrollOffset < -180 ? playlist.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PlaylistMoreMenu(
                    playlist: playlist,
                    songs: songs
                )
            }
        }
        .animation(
            reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
            value: scrollOffset < -180
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
            value: songs.count
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
            value: loader.isLoading
        )
        .scrollIndicators(.hidden)
        .musicScreenBackground()
        .refreshable {
            AppHaptic.selection.play()
            loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
        }
        .onAppear {
            loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            RecentlyPlayedStore.shared.record(playlist)
            prefetchArtwork(songs: songs)
        }
        .onChange(of: songs.map(\.id)) { _, _ in
            prefetchArtwork(songs: songs)
        }
        .onChange(of: favorites.favoriteIDs) { _, _ in
            guard playlist.isFavorites else { return }
            loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
        }
    }

    private func prefetchArtwork(songs: [Song]) {
        ArtworkPrefetcher.shared.prefetchPlaylists([playlist], limit: 6, reason: "playlist cover")
        ArtworkPrefetcher.shared.prefetchSongs(
            Array(songs.prefix(18)),
            limit: 18,
            reason: "playlist songs"
        )
    }

    @ViewBuilder
    private func playlistOverview(songs: [Song], width: CGFloat) -> some View {
        if usesWideOverview(availableWidth: width) {
            widePlaylistOverview(songs: songs)
        } else {
            compactPlaylistOverview(songs: songs, width: width)
        }
    }

    private func compactPlaylistOverview(songs: [Song], width: CGFloat) -> some View {
        VStack(spacing: 18) {
            parallaxHero(width: width)
                .contextMenu {
                    PlaylistActionsMenuItems(playlist: playlist, songs: songs)
                } preview: {
                    PlaylistDetailContextPreview(
                        playlist: playlist,
                        songs: songs,
                        coverURLs: playlistCoverURLs
                    )
                }
            playlistTitleBlock(alignment: .center)
            playlistSongsContent(songs: songs)
        }
    }

    private func widePlaylistOverview(songs: [Song]) -> some View {
        HStack(alignment: .top, spacing: AM.Spacing.xxl) {
            VStack(alignment: .leading, spacing: AM.Spacing.l) {
                playlistArtwork(size: 280)
                    .contextMenu {
                        PlaylistActionsMenuItems(playlist: playlist, songs: songs)
                    } preview: {
                        PlaylistDetailContextPreview(
                            playlist: playlist,
                            songs: songs,
                            coverURLs: playlistCoverURLs
                        )
                    }
                playlistTitleBlock(alignment: .leading)
                if !songs.isEmpty {
                    actionButtons(songs: songs, horizontalPadding: 0)
                }
            }
            .frame(width: 320, alignment: .topLeading)

            playlistSongsContent(songs: songs, isWideOverview: true, rowHorizontalPadding: 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 1120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.top, AM.Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlaylistDetail.WideOverview")
    }

    private var playlistCoverURLs: [URL] {
        if let url = playlist.explicitCoverURL {
            return [url]
        }
        let songURLs = Playlist.songArtworkURLs(loader.songs ?? playlist.songListDTOs ?? [], limit: 4)
        if !songURLs.isEmpty {
            return songURLs
        }
        return playlist.initialMosaicArtworkURLs
    }

    private func parallaxHero(width: CGFloat) -> some View {
        let baseSize: CGFloat = 240
        let stretch = reduceMotion ? 0 : max(0, scrollOffset)
        let shrink = reduceMotion ? 0 : max(0, -scrollOffset * 0.4)
        let size = max(140, baseSize + stretch * 0.6 - shrink)
        let yOffset = reduceMotion ? 0 : (scrollOffset > 0 ? -scrollOffset / 2 : 0)
        let artworkOpacity = reduceMotion ? 1 : 1 - min(0.7, max(0, -scrollOffset / 250))
        return playlistArtwork(size: size)
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
            .opacity(artworkOpacity)
            .frame(width: width)
            .offset(y: yOffset)
            .padding(.top, 12)
    }

    private func playlistArtwork(size: CGFloat) -> some View {
        PlaylistArtworkContent(playlist: playlist, coverURLs: playlistCoverURLs, cornerRadius: 14)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func playlistTitleBlock(alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 4) {
            Text(playlist.name)
                .font(.title2.bold())
                .multilineTextAlignment(alignment)
            Text(songCountText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .leading ? 0 : AM.Spacing.screenMargin)
    }

    private var songCountText: String {
        let songs = loader.songs ?? playlist.songListDTOs ?? []
        return SongCountText.songs(songs.isEmpty ? playlist.songCount : songs.count)
    }

    @ViewBuilder
    private func playlistSongsContent(
        songs: [Song],
        isWideOverview: Bool = false,
        rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        if !songs.isEmpty {
            let showsRowArtwork = songs.count <= 200
            VStack(spacing: 0) {
                if !isWideOverview {
                    actionButtons(songs: songs)
                }
                LazyVStack(spacing: 0) {
                    ForEach(songs) { song in
                        Button {
                            play(song, context: songs)
                        } label: {
                            PlaylistRow(song: song, showsArtwork: showsRowArtwork, horizontalPadding: rowHorizontalPadding)
                                .contentShape(Rectangle())
                                .songRowAccessibility(song: song) {
                                    play(song, context: songs)
                                }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .accessibilityIdentifier("PlaylistDetail.song.\(song.id)")
                        Divider().padding(.leading, rowHorizontalPadding + 60)
                    }
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        } else if loader.isLoading {
            PlaylistLoadingRows(horizontalPadding: rowHorizontalPadding)
                .transition(.opacity)
        } else {
            PlaylistEmptyStateView(
                isFavorites: playlist.isFavorites,
                message: loader.emptyStateMessage
            ) {
                loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            }
            .padding(.top, 14)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func actionButtons(
        songs: [Song],
        horizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                if let first = songs.first {
                    AppHaptic.selection.play()
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Play playlist")
            Button {
                AppHaptic.selection.play()
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Shuffle playlist")
        }
        .padding(.horizontal, horizontalPadding)
    }

    private func play(_ song: Song, context: [Song]) {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: context)
    }
}

private struct PlaylistLoadingRows: View {
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin

    var body: some View {
        CenteredLoadingView(label: "Loading playlist songs")
    }
}

private struct PlaylistEmptyStateView: View {
    let isFavorites: Bool
    let message: String
    let onRefresh: () -> Void
    private var title: String {
        isFavorites ? "No Favorites Yet" : "No Songs"
    }

    private var resolvedMessage: String {
        guard !message.hasPrefix("The playlist") else { return message }
        if isFavorites {
            return "Favorite songs to build this playlist automatically."
        }
        return message
    }

    var body: some View {
        VStack(spacing: 16) {
            MusicEmptyState(title: title, message: resolvedMessage)
            MusicEmptyActionButton(title: "Refresh") {
                onRefresh()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct PlaylistDetailContextPreview: View {
    let playlist: Playlist
    let songs: [Song]
    let coverURLs: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaylistArtworkContent(playlist: playlist, coverURLs: coverURLs, cornerRadius: 10)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.isFavorites ? "Favorites" : "Playlist")
                    .font(.caption.bold())
                    .foregroundStyle(Color.appAccent)
                    .textCase(.uppercase)
                Text(playlist.name)
                    .font(AM.Font.tileTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(SongCountText.songs(songs.isEmpty ? playlist.songCount : songs.count))
                    .font(AM.Font.tileCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(width: 252, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PlaylistMoreMenu: View {
    let playlist: Playlist
    let songs: [Song]
    var body: some View {
        Menu {
            PlaylistActionsMenuItems(playlist: playlist, songs: songs)
        } label: {
            Label("More Actions", systemImage: "ellipsis")
                .font(.headline)
                .foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .labelStyle(.iconOnly)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
    }
}

struct PlaylistActionsMenuItems: View {
    let playlist: Playlist
    let songs: [Song]
    @ObservedObject private var savedStore: SavedPlaylistsStore = .shared
    private let pendingSongs: [Song]
    private let inFlightCount: Int
    private var pendingCount: Int {
        pendingSongs.count
    }

    private var allDownloaded: Bool {
        !songs.isEmpty && pendingCount == 0 && inFlightCount == 0
    }

    private var canSaveToLibrary: Bool {
        !playlist.isFavorites && !playlist.isPersonal
    }

    private var isSaved: Bool {
        savedStore.isSaved(playlist)
    }

    init(playlist: Playlist, songs: [Song]) {
        self.playlist = playlist
        self.songs = songs

        let downloads = DownloadManager.shared
        pendingSongs = songs.filter { !downloads.isDownloaded($0.id) && !downloads.isDownloading($0.id) }
        inFlightCount = songs.filter { downloads.isDownloading($0.id) }.count
    }

    var body: some View {
        if !songs.isEmpty {
            Button {
                AppHaptic.selection.play()
                if let first = songs.first {
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                AppHaptic.selection.play()
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }

            Divider()
        }

        if canSaveToLibrary {
            Button {
                AppHaptic.selection.play()
                savedStore.toggle(playlist)
            } label: {
                if isSaved {
                    Label("Remove from Library", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Add to Library", systemImage: "plus.circle")
                }
            }
        }

        if !songs.isEmpty {
            if inFlightCount > 0 {
                Label("Downloading \(inFlightCount)…", systemImage: "arrow.down.circle")
            } else if allDownloaded {
                Button(role: .destructive) {
                    AppHaptic.warning.play()
                    for s in songs {
                        DownloadManager.shared.remove(songID: s.id)
                    }
                } label: {
                    Label("Remove Downloads", systemImage: "trash")
                }
            } else {
                Button {
                    AppHaptic.success.play()
                    for s in pendingSongs {
                        DownloadManager.shared.download(song: s)
                    }
                } label: {
                    let label = pendingCount < songs.count ? "Download Remaining" : "Download"
                    Label(label, systemImage: "arrow.down.circle")
                }
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private func quantizedScrollOffset(_ offset: CGFloat) -> CGFloat {
    (offset / 8).rounded() * 8
}

struct PlaylistRow: View {
    let song: Song

    var showsArtwork = true
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin

    var body: some View {
        SongRow(song: song, size: .regular, showsArtwork: showsArtwork)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
    }
}

@MainActor
class PlaylistDetailViewModel: ObservableObject {
    @Published var songs: [Song]?
    @Published var isLoading = false
    @Published private var loadFailed = false
    private var loadedID: String?
    private var loadTask: Task<Void, Never>?
    var emptyStateMessage: String {
        if loadFailed {
            return "The playlist couldn’t be loaded. Check your connection and try again."
        }
        return "Pull down or tap refresh to check for new songs."
    }

    func reload(playlistID: String, fallback: [Song]? = nil) {
        loadedID = nil
        loadFailed = false
        load(playlistID: playlistID, fallback: fallback)
    }

    func load(playlistID: String, fallback: [Song]?) {
        let alreadyLoaded = (loadedID == playlistID) && songs != nil && !isLoading
        if alreadyLoaded { return }
        loadedID = playlistID
        loadTask?.cancel()
        if songs?.isEmpty ?? true, let fallback, !fallback.isEmpty {
            songs = fallback
        }
        if AppRuntime.isUITestMode,
           let fallback, !fallback.isEmpty
        {
            loadTask = nil
            songs = fallback
            isLoading = false
            loadFailed = false
            return
        }
        isLoading = true
        loadTask = Task { [weak self] in
            do {
                let loadedSongs = try await KaraokeAPIClient.playlistSongs(id: playlistID)
                guard !Task.isCancelled else { return }
                self?.applyLoadedSongs(
                    loadedSongs,
                    playlistID: playlistID,
                    requestFailed: false
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyLoadedSongs(nil, playlistID: playlistID, requestFailed: true)
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func applyLoadedSongs(_ list: [Song]?, playlistID: String, requestFailed: Bool) {
        guard loadedID == playlistID else { return }
        if let list {
            songs = list
        }
        loadFailed = requestFailed && (songs?.isEmpty ?? true)
        isLoading = false
    }
}
