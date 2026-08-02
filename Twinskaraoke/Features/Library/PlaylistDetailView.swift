import SwiftUI

struct PlaylistDetailView: View {
    private static let searchFieldHeight: CGFloat = 40

    let playlist: Playlist
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var loader = PlaylistDetailViewModel()
    private let favorites = FavoritesManager.shared
    // Rows derive artwork URLs through `Song`, which consults the fallback
    // pool; reading the revision in `body` re-renders them when it changes.
    private let fallbackArt = FallbackArtRevision.shared
    @State private var showsCollapsedTitle = false
    @State private var searchText = ""
    @State private var filteredSongs: [Song]
    @State private var isSearchVisible = false
    @State private var isSearchModeActive = false
    @State private var artworkPullOverride: CGFloat = 0
    @State private var isArtworkPullOverridden = false
    @State private var canAutoHideSearch = false
    @State private var isActivelyPulling = false
    @State private var shouldActivateSearchAfterPull = false
    @State private var searchRevealState = PlaylistSearchRevealState()
    @State private var filterTask: Task<Void, Never>?
    @State private var favoritesRefreshTask: Task<Void, Never>?
    @State private var prefetchedIDs: [String] = []
    @FocusState private var isSearchFocused: Bool

    init(playlist: Playlist) {
        self.playlist = playlist
        // searchText starts empty, so the initial filtered list is the fallback.
        _filteredSongs = State(initialValue: playlist.songListDTOs ?? [])
    }

    private func usesWideOverview(availableWidth: CGFloat) -> Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }


    var body: some View {
        let _ = fallbackArt.revision
        let songs: [Song] = loader.songs ?? playlist.songListDTOs ?? []
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Derive the unfiltered list rather than mirroring it into @State.
        //
        // `filteredSongs` is only meaningful while a search is active. Using it
        // as the sole source made the whole screen depend on a sync that had no
        // way to self-correct: if it was ever missed, the list stayed empty and
        // stayed empty. See the `onChange(of: loader.songs)` note below.
        let displayedSongs = isSearching ? filteredSongs : songs
        GeometryReader { geo in
            ScrollView {
                playlistScrollContent(
                    songs: songs,
                    displayedSongs: displayedSongs,
                    isSearching: isSearching,
                    width: geo.size.width
                )
                    .padding(.bottom, 16)
                    // Row changes (e.g. unfavouriting) used to animate via the
                    // `filteredSongs` swap; now that the list is derived, the
                    // animation attaches to the value instead. Same 300-row
                    // guard: animating a large structural swap stalls the main
                    // thread.
                    .animation(
                        reduceMotion || displayedSongs.count >= 300
                            ? nil
                            : AppMotion.quick,
                        value: displayedSongs
                    )
            }
            .smoothScrolling()
            .scrollDismissesKeyboard(.interactively)
            .bottomChromeScrollTracking()
            .collapsedNavigationTitle($showsCollapsedTitle)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, scrollOffset in
                // Defer out of the geometry-update pass: updateSearchInteraction
                // toggles the search safe-area inset and hero pull override,
                // which changes this geometry in the same frame — SwiftUI then
                // logs "tried to update multiple times per frame" and drops
                // the intermediate scroll events. main.async is enough here:
                // lighter than a Task per scroll event and strictly FIFO.
                //
                // Coalescing these to one update per runloop turn *does* silence
                // that log (and the `<width>x0` offscreen-buffer errors from the
                // search field animating through zero height), but it visibly
                // hurt fast-scroll feel: the pull/parallax logic needs the
                // intermediate offsets, not just the newest one. The log noise
                // is cosmetic; the scroll feel is not. Left as-is deliberately.
                DispatchQueue.main.async {
                    updateSearchInteraction(scrollOffset: scrollOffset)
                }
            }
            .onScrollPhaseChange { _, phase in
                let wasActivelyPulling = isActivelyPulling
                isActivelyPulling = phase == .tracking || phase == .interacting
                if wasActivelyPulling, !isActivelyPulling {
                    if isArtworkPullOverridden {
                        withAnimation(reduceMotion ? nil : AppMotion.easeOut(duration: 0.24)) {
                            artworkPullOverride = 0
                        } completion: {
                            guard artworkPullOverride == 0 else { return }
                            isArtworkPullOverridden = false
                        }
                    }
                    activateSearchAfterPull()
                }
            }
        }
        .navigationTitle(showsCollapsedTitle && !isSearchModeActive ? playlist.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(showsCollapsedTitle ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PlaylistMoreMenu(
                    playlist: playlist,
                    songs: songs,
                    onRefresh: refresh
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isSearchVisible {
                playlistSearchField
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
            }
        }
        .animation(
            reduceMotion ? nil : AppMotion.quick,
            value: showsCollapsedTitle
        )
        // No animation for isLoading / isSearchModeActive flips — neither a
        // container .animation(value:) nor an explicit withAnimation at any
        // mutation site (activateSearchAfterPull, the isSearchFocused change,
        // dismissSearch, auto-hide; marked "Unanimated on purpose" below).
        // Animating the whole scroll-content swap makes SwiftUI re-measure
        // every row of a large playlist per frame and hangs the main thread
        // (watchdog kill) on big playlists. The section-level
        // .transition(.opacity) modifiers still animate the swap cheaply.
        .scrollIndicators(.hidden)
        .musicScreenBackground()
        .onAppear {
            loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            RecentlyPlayedStore.shared.record(playlist)
            prefetchedIDs = Array(displayedSongs.prefix(18)).map(\.id)
            prefetchArtwork(songs: displayedSongs)
        }
        // Diffing on displayedSongs (Equatable) avoids allocating the prefix
        // id array on every body eval; it only builds when the list changes.
        .onChange(of: displayedSongs) { _, newSongs in
            let ids = Array(newSongs.prefix(18)).map(\.id)
            guard ids != prefetchedIDs else { return }
            prefetchedIDs = ids
            prefetchArtwork(songs: newSongs)
        }
        .onChange(of: searchText) { _, newValue in
            // Filtering a large playlist runs 3 localized comparisons per song;
            // debounce so typing doesn't stall the main thread per keystroke.
            filterTask?.cancel()
            filterTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                // Resolve the source list now, not at body-eval time, so a
                // loader.$songs update during the debounce isn't overwritten
                // by a filter of the stale snapshot.
                let currentSongs = loader.songs ?? playlist.songListDTOs ?? []
                filteredSongs = PlaylistSongSearch.filter(currentSongs, matching: newValue)
            }
        }
        // Keeps the *search* results fresh when the playlist reloads underneath
        // an active query. It deliberately no longer feeds the unfiltered list.
        //
        // This was `.onReceive(loader.$songs)`, and the two are not equivalent.
        // A `@Published` projected publisher replays its current value to every
        // new subscriber, so that fired on each appear and re-seeded the list
        // unconditionally. `onChange` fires neither on install nor when the new
        // value compares equal to the old. Both gaps bit: a playlist already
        // loaded when the view appeared never seeded, and Refresh re-fetched an
        // *equal* array, so nothing fired and the empty list could not recover
        // until the view was destroyed by popping back to Library.
        .onChange(of: loader.songs) { _, newSongs in
            let next = PlaylistSongSearch.filter(
                newSongs ?? playlist.songListDTOs ?? [],
                matching: searchText
            )
            // Animating a huge structural swap can stall the main thread;
            // only animate small list changes (e.g. unfavoriting a row).
            let canAnimate = filteredSongs.count < 300 && next.count < 300
            withOptionalAnimation(reduceMotion || !canAnimate ? nil : AppMotion.quick) {
                filteredSongs = next
            }
        }
        .onChange(of: favorites.favoriteIDs) { _, _ in
            guard playlist.isFavorites else { return }
            // Every star tap anywhere in the app fires this; coalesce rapid
            // toggles into a single refetch instead of reloading the whole
            // playlist per tap.
            favoritesRefreshTask?.cancel()
            favoritesRefreshTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            }
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            guard isFocused, !isSearchModeActive else { return }
            shouldActivateSearchAfterPull = false
            isArtworkPullOverridden = false
            // Unanimated on purpose (see "No animation" note above).
            isSearchModeActive = true
        }
        .onDisappear {
            ArtworkPrefetcher.shared.cancel(reason: "playlist cover \(playlist.id)")
            ArtworkPrefetcher.shared.cancel(reason: "playlist songs \(playlist.id)")
        }
    }

    @ViewBuilder
    private func playlistScrollContent(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        width: CGFloat
    ) -> some View {
        if isSearchModeActive {
            playlistSongsContent(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching,
                showsActionButtons: false
            )
            .padding(.top, AM.Spacing.xs)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.98))
            )
            .accessibilityIdentifier("PlaylistDetail.SearchResults")
        } else {
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
        }
    }

    private var playlistSearchField: some View {
        HStack(spacing: AM.Spacing.s) {
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
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Self.searchFieldHeight)
            .background(.thinMaterial, in: Capsule())

            if isSearchModeActive {
                Button("Cancel") {
                    dismissSearch()
                }
                .foregroundStyle(Color.appAccent)
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.top, AM.Spacing.s)
        .padding(.bottom, AM.Spacing.m)
        .animation(reduceMotion ? nil : AppMotion.quick, value: isSearchModeActive)
        .accessibilityIdentifier("PlaylistDetail.search")
    }

    private func updateSearchInteraction(scrollOffset: CGFloat) {
        let pullDistance = max(0, -scrollOffset)

        if searchRevealState.update(
            pullDistance: pullDistance,
            isSearchVisible: isSearchVisible,
            isActivelyPulling: isActivelyPulling
        ) {
            AppHaptic.medium.play()
            canAutoHideSearch = false
            artworkPullOverride = reduceMotion
                ? 0
                : min(pullDistance, PlaylistSearchRevealState.revealThreshold)
            isArtworkPullOverridden = !reduceMotion
            shouldActivateSearchAfterPull = true
            withAnimation(reduceMotion ? nil : AppMotion.snap) {
                isSearchVisible = true
            }
        }

        guard isSearchVisible else { return }

        if abs(scrollOffset) <= PlaylistSearchRevealState.resetThreshold {
            canAutoHideSearch = true
            return
        }

        guard PlaylistSearchRevealState.shouldAutoHide(
            scrollOffset: scrollOffset,
            isReady: canAutoHideSearch,
            isActivelyScrolling: isActivelyPulling,
            isSearchModeActive: isSearchModeActive
        ) else { return }

        isSearchFocused = false
        searchText = ""
        canAutoHideSearch = false
        shouldActivateSearchAfterPull = false
        // Unanimated on purpose (see "No animation" note above); only the
        // search field inset and hero override animate.
        isSearchModeActive = false
        withAnimation(reduceMotion ? nil : AppMotion.quick) {
            isSearchVisible = false
            isArtworkPullOverridden = false
        }
    }

    private func dismissSearch() {
        isSearchFocused = false
        searchText = ""
        canAutoHideSearch = false
        shouldActivateSearchAfterPull = false
        searchRevealState.reset()
        // Unanimated on purpose (see "No animation" note above); only the
        // search field inset and hero override animate.
        isSearchModeActive = false
        withAnimation(reduceMotion ? nil : AppMotion.quick) {
            isSearchVisible = false
            isArtworkPullOverridden = false
        }
    }

    private func activateSearchAfterPull() {
        guard shouldActivateSearchAfterPull, isSearchVisible else { return }
        shouldActivateSearchAfterPull = false

        // Unanimated on purpose (see "No animation" note above).
        isSearchModeActive = true
        Task { @MainActor in
            await Task.yield()
            guard isSearchVisible, isSearchModeActive else { return }
            isSearchFocused = true
        }
    }

    private func refresh() {
        AppHaptic.selection.play()
        loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
    }

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
        // The windowed prefetch above only stays just ahead of the visible
        // rows, which a fast flick outruns. Warm the *whole* playlist onto disk
        // as well, so a second visit scrolls with no placeholders at all.
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
                pullDownOverride: isArtworkPullOverridden ? artworkPullOverride : nil
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
            }
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

/// Row identity for the playlist song list. The offset keeps IDs unique when
/// a playlist contains the same song twice (duplicate ForEach IDs can hang
/// AttributeGraph). The content fields make the ID change when metadata
/// (artist, duration) arrives after a row was first composed: with purely
/// positional identity, an already-composed row keeps showing the stale
/// "Unknown Artist" from the artist-less list DTOs even after the detail
/// fetch lands, until the whole list is torn down and rebuilt.
private struct PositionedPlaylistSong: Identifiable {
    struct ID: Hashable {
        let offset: Int
        let songID: String
        let displayArtist: String
        let durationText: String
    }

    let offset: Int
    let song: Song

    var id: ID {
        ID(
            offset: offset,
            songID: song.id,
            displayArtist: song.displayArtist,
            durationText: song.durationText
        )
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
        ContextPreviewCard {
            PlaylistArtworkContent(playlist: playlist, coverURLs: coverURLs, cornerRadius: 10)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    var body: some View {
        Menu {
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
    }
}
