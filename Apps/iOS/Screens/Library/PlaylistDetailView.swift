import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var loader = PlaylistDetailViewModel()
    private let favorites = FavoritesManager.shared
    private let fallbackArt = FallbackArtRevision.shared
    @State private var searchText = ""
    @State private var contentWidth: CGFloat = 390
    @FocusState private var isSearchFocused: Bool
    private static let searchFieldExtent: CGFloat = 52
    private static let searchDismissDistance: CGFloat = 40
    private static let searchRevealDeadZone: CGFloat = 30
    private static let searchRevealResistance: CGFloat = 0.65
    private static let searchPullStep: CGFloat = 2
    @State private var searchRevealHeight: CGFloat = 0
    @State private var showsCollapsedTitle = false
    @State private var isSearchLatched = false

    private static let searchAnchor = "playlist.search"
    private static let contentAnchor = "playlist.content"
    @State private var filteredSongs: [Song]
    @State private var filterTask: Task<Void, Never>?
    @State private var favoritesRefreshTask: Task<Void, Never>?
    @State private var prefetchedIDs: [String] = []
    /// The full list the whole-playlist warm last covered this visit.
    @State private var warmedSongIDs: [String] = []
    @State private var prefetchTask: Task<Void, Never>?
    @State private var removalErrorSong: Song?
    @State private var isEditing = false
    @Environment(\.zoomPushIsArriving) private var isArriving
    @State private var hasSettledAfterAppear = false
    @State private var rowArmingTask: Task<Void, Never>?
    private var playbackTapsArmed: Bool { hasSettledAfterAppear && !isArriving }
    @State private var hasStartedVisit = false
    private let userPlaylists = UserPlaylistsManager.shared

    init(playlist: Playlist) {
        self.playlist = playlist
        _filteredSongs = State(initialValue: playlist.songListDTOs ?? [])
    }

    private var playlistSearchField: some View {
        HStack(spacing: AM.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in Playlist", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("PlaylistDetail.searchField")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .appGlassBackground(in: Capsule())
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.bottom, AM.Spacing.m)
        .accessibilityIdentifier("PlaylistDetail.search")
    }
    private func updateSearchReveal(pull: CGFloat) {
        let extent = Self.searchFieldExtent
        if isSearchLatched {
            if pull < -Self.searchDismissDistance, !isSearchFocused, searchText.isEmpty {
                isSearchLatched = false
                withOptionalAnimation(reduceMotion ? nil : AppMotion.quick) {
                    searchRevealHeight = 0
                }
            } else if searchRevealHeight != extent {
                searchRevealHeight = extent
            }
            return
        }
        let effective = max(0, pull - Self.searchRevealDeadZone) * Self.searchRevealResistance
        let revealed = min(effective, extent)
        if revealed >= extent {
            isSearchLatched = true
            AppHaptic.boundary.play()
            withOptionalAnimation(reduceMotion ? nil : AppMotion.snap) {
                searchRevealHeight = extent
            }
        } else if searchRevealHeight != revealed {
            searchRevealHeight = revealed
        }
    }

    /// Held back until the transition has run: warmCollection derives a URL for
    /// every song, and doing that inside the transition window competes with the
    /// animation.
    ///
    /// The list is read when the task fires, not when it is scheduled. Capturing
    /// `displayedSongs` from `body` snapshotted the `songListDTOs` fallback,
    /// because `loader.songs` is still nil at that point — so if the fetch landed
    /// inside the delay, this overwrote the authoritative warm with the stale one
    /// under the same reason key, and clobbered `prefetchedIDs` with it.
    ///
    /// Until it runs, the `displayedSongs` and `loader.songs` observers stand
    /// aside (they check `prefetchTask`). Songs usually arrive well inside the
    /// 400ms, and an observer prefetching them too warmed every playlist twice,
    /// the first time inside the very transition this delay keeps clear.
    private func schedulePrefetch() {
        prefetchTask?.cancel()
        prefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            prefetchTask = nil
            let songs = loader.songs ?? playlist.songListDTOs ?? []
            guard !songs.isEmpty else { return }
            // The window follows what the list shows, as the displayedSongs
            // observer's does: a search opened inside the delay is showing
            // its results, and that observer stood aside meanwhile. The warm
            // still covers the whole playlist.
            let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let displayed = isSearching ? filteredSongs : songs
            prefetchedIDs = Array(displayed.prefix(18)).map(\.id)
            prefetchArtwork(songs: displayed)
            warmCollectionIfNeeded()
        }
    }

    private func usesWideOverview(availableWidth: CGFloat) -> Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }


    var body: some View {
        detailContent
            .fullScreenCover(isPresented: $isEditing) {
                if let editTarget {
                    NavigationStack {
                        PlaylistEditView(
                            playlistName: playlist.name,
                            songs: loader.songs ?? playlist.songListDTOs ?? [],
                            target: editTarget
                        ) { reordered in
                            loader.songs = reordered
                        }
                    }
                }
            }
    }
    private var editTarget: PlaylistEditTarget? {
        if playlist.isFavorites { return .favorites }
        guard userPlaylists.playlists.contains(where: { $0.id == playlist.id }) else {
            return nil
        }
        return .playlist(id: playlist.id)
    }
    private var editAction: (() -> Void)? {
        guard editTarget != nil, loader.hasAuthoritativeSongs else { return nil }
        return beginEditing
    }

    private func beginEditing() {
        searchText = ""
        filteredSongs = loader.songs ?? playlist.songListDTOs ?? []
        isSearchFocused = false
        AppHaptic.selection.play()
        isEditing = true
    }
    @ViewBuilder
    private var detailContent: some View {
        let _ = fallbackArt.revision
        let songs: [Song] = loader.songs ?? playlist.songListDTOs ?? []
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let displayedSongs = isSearching ? filteredSongs : songs
        ScrollView {
            VStack(spacing: 0) {
                playlistSearchField
                    .frame(height: searchRevealHeight, alignment: .bottom)
                    .opacity(searchRevealHeight / Self.searchFieldExtent)
                    .clipped()
                    .allowsHitTesting(searchRevealHeight > 0)
                    .accessibilityHidden(searchRevealHeight <= 0)
                    .zIndex(1)
                    .id(Self.searchAnchor)
                playlistScrollContent(
                    songs: songs,
                    displayedSongs: displayedSongs,
                    isSearching: isSearching,
                    width: contentWidth
                )
                .id(Self.contentAnchor)
            }
                .padding(.bottom, 16)
                .animation(
                    reduceMotion || displayedSongs.count >= 300
                        ? nil
                        : AppMotion.quick,
                    value: displayedSongs
                )
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.width
        } action: { _, width in
            guard width > 0, abs(width - contentWidth) > 0.5 else { return }
            contentWidth = width
        }
        .smoothScrolling()
        .scrollEdgeHaptic()
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let pull = -(geometry.contentOffset.y + geometry.contentInsets.top)
            return (pull / Self.searchPullStep).rounded() * Self.searchPullStep
        } action: { _, pull in
            updateSearchReveal(pull: pull)
        }
        .scrollIndicators(.hidden)
        .collapsedNavigationTitle($showsCollapsedTitle)
        .musicScreenBackground()
        .navigationTitle(showsCollapsedTitle ? playlist.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(showsCollapsedTitle ? .visible : .hidden, for: .navigationBar)
        .animation(
            reduceMotion ? nil : AppMotion.quick,
            value: showsCollapsedTitle
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PlaylistMoreMenu(
                    playlist: playlist,
                    songs: songs,
                    onRefresh: refresh,
                    onEdit: editAction
                )
            }
        }
        .alert(
            "Couldn't Remove Song",
            isPresented: Binding(
                get: { removalErrorSong != nil },
                set: { if !$0 { removalErrorSong = nil } }
            ),
            presenting: removalErrorSong
        ) { _ in
            Button("OK", role: .cancel) { removalErrorSong = nil }
        } message: { song in
            Text("\(song.title) is still in \(playlist.name). Check your connection and try again.")
        }
        .onAppear {
            rowArmingTask?.cancel()
            rowArmingTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                hasSettledAfterAppear = true
            }
            schedulePrefetch()

            guard !hasStartedVisit else { return }
            hasStartedVisit = true
            loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            userPlaylists.loadIfNeeded()
        }
        .onChange(of: displayedSongs) { _, newSongs in
            guard prefetchTask == nil else { return }
            let ids = Array(newSongs.prefix(18)).map(\.id)
            guard ids != prefetchedIDs else { return }
            prefetchedIDs = ids
            prefetchArtwork(songs: newSongs)
        }
        .onChange(of: searchText) { _, newValue in
            filterTask?.cancel()
            filterTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let currentSongs = loader.songs ?? playlist.songListDTOs ?? []
                filteredSongs = PlaylistSongSearch.filter(currentSongs, matching: newValue)
            }
        }
        .onChange(of: loader.songs) { _, newSongs in
            let next = PlaylistSongSearch.filter(
                newSongs ?? playlist.songListDTOs ?? [],
                matching: searchText
            )
            let canAnimate = filteredSongs.count < 300 && next.count < 300
            withOptionalAnimation(reduceMotion || !canAnimate ? nil : AppMotion.quick) {
                filteredSongs = next
            }
            // The warm follows the loaded list, not the displayed one, so
            // songs that arrive while a search is open are still warmed.
            if prefetchTask == nil {
                warmCollectionIfNeeded()
            }
        }
        .onChange(of: favorites.favoriteIDs) { _, _ in
            guard playlist.isFavorites else { return }
            favoritesRefreshTask?.cancel()
            favoritesRefreshTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            }
        }
        .onDisappear {
            rowArmingTask?.cancel()
            hasSettledAfterAppear = false
            prefetchTask?.cancel()
            filterTask?.cancel()
            favoritesRefreshTask?.cancel()
            ArtworkPrefetcher.shared.cancel(reason: "playlist cover \(playlist.id)")
            ArtworkPrefetcher.shared.cancel(reason: "playlist songs \(playlist.id)")
            ArtworkPrefetcher.shared.cancelWarm(reason: "playlist warm \(playlist.id)")
            warmedSongIDs = []
        }
    }

    @ViewBuilder
    private func playlistScrollContent(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        width: CGFloat
    ) -> some View {
        playlistOverview(
            songs: songs,
            displayedSongs: displayedSongs,
            isSearching: isSearching,
            width: width
        )
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.98))
        )
        .accessibilityIdentifier(isSearching ? "PlaylistDetail.SearchResults" : "PlaylistDetail.Overview")
    }

    private func refresh() {
        AppHaptic.selection.play()
        loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
    }

    /// The cover and the rows just ahead of the visible ones.
    private func prefetchArtwork(songs: [Song]) {
        ArtworkPrefetcher.shared.prefetchPlaylists(
            [playlist],
            limit: 6,
            reason: "playlist cover \(playlist.id)",
            variant: .thumbnail
        )
        ArtworkPrefetcher.shared.prefetchSongs(
            Array(songs.prefix(ArtworkPrefetcher.songWindow)),
            reason: "playlist songs \(playlist.id)",
            variant: .row
        )
    }

    /// The windowed prefetch only stays just ahead of the visible rows, which
    /// a fast flick outruns. This warms the *whole* playlist onto disk as well,
    /// so a second visit scrolls with no placeholders at all.
    ///
    /// It reads the full list rather than taking the displayed one. Search
    /// results are a subset, and warming them under the same reason key
    /// cancelled the full warm partway through a long playlist. It also skips
    /// a list it has already warmed this visit, so a search, or a refresh that
    /// returns the same songs, does not start it again.
    private func warmCollectionIfNeeded() {
        let songs = loader.songs ?? playlist.songListDTOs ?? []
        let ids = songs.map(\.id)
        guard !ids.isEmpty, ids != warmedSongIDs else { return }
        warmedSongIDs = ids
        ArtworkPrefetcher.shared.warmCollection(
            songs: songs,
            reason: "playlist warm \(playlist.id)",
            variant: .row
        )
    }

    @ViewBuilder
    private func playlistOverview(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        width: CGFloat
    ) -> some View {
        if usesWideOverview(availableWidth: width) {
            widePlaylistOverview(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching
            )
        } else {
            compactPlaylistOverview(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching,
                width: width
            )
        }
    }

    private func compactPlaylistOverview(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        width: CGFloat
    ) -> some View {
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
            playlistSongsContent(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching
            )
        }
    }

    private func widePlaylistOverview(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool
    ) -> some View {
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
                if !displayedSongs.isEmpty {
                    actionButtons(songs: displayedSongs, horizontalPadding: 0)
                }
            }
            .frame(width: 320, alignment: .topLeading)

            playlistSongsContent(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching,
                isWideOverview: true,
                rowHorizontalPadding: 0
            )
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
        return playlistArtwork(size: baseSize)
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
            .frame(width: width)
            .frame(height: baseSize)
            .scrollParallaxHero(
                baseSize: baseSize,
                restingOffset: 12,
                fadesWhenCollapsed: true,
                reduceMotion: reduceMotion,
                pullDownOverride: 0
            )
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
            if let songCountText {
                Text(songCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .leading ? 0 : AM.Spacing.screenMargin)
    }

    private var songCountText: String? {
        guard loader.hasAuthoritativeSongs else { return nil }
        let songs = loader.songs ?? playlist.songListDTOs ?? []
        return SongCountText.songs(songs.count)
    }

    @ViewBuilder
    private func playlistSongsContent(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        isWideOverview: Bool = false,
        showsActionButtons: Bool = true,
        rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        if !displayedSongs.isEmpty {
            VStack(spacing: 0) {
                if showsActionButtons, !isWideOverview {
                    actionButtons(songs: displayedSongs)
                }
                LazyVStack(spacing: 0) {
                    ForEach(displayedSongs.enumerated().map { PositionedPlaylistSong(offset: $0.offset, song: $0.element) }) { item in
                        Button {
                            play(item.song, context: displayedSongs)
                        } label: {
                            PlaylistRow(song: item.song, showsArtwork: true, horizontalPadding: rowHorizontalPadding)
                                .contentShape(Rectangle())
                                .songRowAccessibility(song: item.song) {
                                    play(item.song, context: displayedSongs)
                                }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .accessibilityIdentifier("PlaylistDetail.song.\(item.offset).\(item.song.id)")
                        if item.offset < displayedSongs.count - 1 {
                            Divider().padding(.leading, rowHorizontalPadding + 60)
                        }
                    }
                }
                .allowsHitTesting(playbackTapsArmed)
            }
            .environment(\.playlistSongRemoval, songRemovalContext)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else if loader.isLoading, songs.isEmpty {
            PlaylistLoadingRows(horizontalPadding: rowHorizontalPadding)
                .transition(.opacity)
        } else if isSearching, !songs.isEmpty {
            MusicEmptyState(
                title: String(localized: "No Results"),
                message: String(localized: "Try another song title or artist.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
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
                    PlaylistPlayback.playInOrder(first, from: playlist, context: songs)
                }
            } label: {
                LibraryActionButtonLabel(symbol: "play.fill", text: String(localized: "Play"))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Play playlist")
            Button {
                AppHaptic.selection.play()
                PlaylistPlayback.playShuffled(from: playlist, songs: songs)
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: String(localized: "Shuffle"))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Shuffle playlist")
        }
        .padding(.horizontal, horizontalPadding)
        .allowsHitTesting(playbackTapsArmed)
    }

    private func play(_ song: Song, context: [Song]) {
        AppHaptic.selection.play()
        PlaylistPlayback.play(song, from: playlist, context: context)
    }
    private var songRemovalContext: PlaylistSongRemovalContext? {
        guard !playlist.isFavorites,
              userPlaylists.playlists.contains(where: { $0.id == playlist.id })
        else { return nil }
        return PlaylistSongRemovalContext(
            playlistID: playlist.id,
            playlistName: playlist.name,
            remove: { song in remove(song) }
        )
    }

    private func remove(_ song: Song) {
        guard let restore = loader.removeSongOptimistically(song) else { return }
        userPlaylists.removeSong(song.id, fromPlaylist: playlist.id) { success in
            guard !success else { return }
            AppHaptic.error.play()
            restore()
            removalErrorSong = song
        }
    }
}
private struct PositionedPlaylistSong: Identifiable {
    struct ID: Hashable {
        let offset: Int
        let songID: String
        let metadata: Song.RowMetadata
    }

    let offset: Int
    let song: Song

    var id: ID {
        ID(
            offset: offset,
            songID: song.id,
            metadata: song.rowMetadata
        )
    }
}

private struct PlaylistLoadingRows: View {
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin

    var body: some View {
        CenteredLoadingView(label: String(localized: "Loading playlist songs"))
    }
}

private struct PlaylistEmptyStateView: View {
    let isFavorites: Bool
    let message: String
    let onRefresh: () -> Void
    private var title: String {
        isFavorites ? String(localized: "No Favorites Yet") : String(localized: "No Songs")
    }

    private var resolvedMessage: String {
        guard !message.hasPrefix("The playlist") else { return message }
        if isFavorites {
            return String(localized: "Favorite songs to build this playlist automatically.")
        }
        return message
    }

    var body: some View {
        VStack(spacing: 16) {
            MusicEmptyState(title: title, message: resolvedMessage)
            MusicEmptyActionButton(title: String(localized: "Refresh")) {
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
        ContextPreviewCard {
            PlaylistArtworkContent(playlist: playlist, coverURLs: coverURLs, cornerRadius: AM.Radius.card)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        } label: {
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
    }
}

private struct PlaylistMoreMenu: View {
    let playlist: Playlist
    let songs: [Song]
    let onRefresh: () -> Void
    var onEdit: (() -> Void)?
    var body: some View {
        Menu {
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Playlist", systemImage: "pencil")
                }
                Divider()
            }
            PlaylistActionsMenuItems(playlist: playlist, songs: songs)
            Divider()
            Button {
                onRefresh()
            } label: {
                Label("Refresh Playlist", systemImage: "arrow.clockwise")
            }
        } label: {
            Label("More Actions", systemImage: "ellipsis")
                .font(.headline)
                .foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .labelStyle(.iconOnly)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
        .accessibilityIdentifier("PlaylistDetail.moreActions")
    }
}
