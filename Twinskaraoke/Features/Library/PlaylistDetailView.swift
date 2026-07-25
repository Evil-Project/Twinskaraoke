import Combine
import SwiftUI

struct PlaylistDetailView: View {
    private static let searchFieldHeight: CGFloat = 40

    let playlist: Playlist
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var loader = PlaylistDetailViewModel()
    @ObservedObject private var favorites = FavoritesManager.shared
    @ObservedObject private var fallbackArt = FallbackArtProvider.shared
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
        let songs: [Song] = loader.songs ?? playlist.songListDTOs ?? []
        let displayedSongs = filteredSongs
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        GeometryReader { geo in
            ScrollView {
                playlistScrollContent(
                    songs: songs,
                    displayedSongs: displayedSongs,
                    isSearching: isSearching,
                    width: geo.size.width
                )
                    .padding(.bottom, 16)
            }
            .smoothScrolling()
            .scrollDismissesKeyboard(.interactively)
            .bottomChromeScrollTracking()
            .collapsedNavigationTitle($showsCollapsedTitle)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, scrollOffset in
                updateSearchInteraction(scrollOffset: scrollOffset)
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
        // No container .animation(value:) for isLoading / isSearchModeActive:
        // an implicit animation on those flips animates the whole scroll
        // content swap, which makes SwiftUI re-measure every row of a large
        // playlist per frame and can hang the main thread. The section-level
        // .transition(.opacity) modifiers still animate the swap cheaply.
        .scrollIndicators(.hidden)
        .musicScreenBackground()
        .onAppear {
            loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            RecentlyPlayedStore.shared.record(playlist)
            prefetchArtwork(songs: displayedSongs)
        }
        .task(id: Array(displayedSongs.prefix(18)).map(\.id)) {
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            prefetchArtwork(songs: displayedSongs)
        }
        .onChange(of: searchText) { _, _ in
            filteredSongs = PlaylistSongSearch.filter(songs, matching: searchText)
        }
        .onReceive(loader.$songs) { newSongs in
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
            loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            guard isFocused, !isSearchModeActive else { return }
            shouldActivateSearchAfterPull = false
            isArtworkPullOverridden = false
            withAnimation(reduceMotion ? nil : AppMotion.quick) {
                isSearchModeActive = true
            }
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
        withAnimation(reduceMotion ? nil : AppMotion.quick) {
            isSearchVisible = false
            isSearchModeActive = false
            isArtworkPullOverridden = false
        }
    }

    private func dismissSearch() {
        isSearchFocused = false
        searchText = ""
        canAutoHideSearch = false
        shouldActivateSearchAfterPull = false
        searchRevealState.reset()
        withAnimation(reduceMotion ? nil : AppMotion.quick) {
            isSearchVisible = false
            isSearchModeActive = false
            isArtworkPullOverridden = false
        }
    }

    private func activateSearchAfterPull() {
        guard shouldActivateSearchAfterPull, isSearchVisible else { return }
        shouldActivateSearchAfterPull = false

        withAnimation(reduceMotion ? nil : AppMotion.easeOut(duration: 0.18)) {
            isSearchModeActive = true
        } completion: {
            Task { @MainActor in
                await Task.yield()
                guard isSearchVisible, isSearchModeActive else { return }
                isSearchFocused = true
            }
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
            Array(songs.prefix(18)),
            limit: 18,
            reason: "playlist songs \(playlist.id)",
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
                    // Positional identity: playlists can contain the same song
                    // twice, and duplicate ForEach IDs can hang AttributeGraph.
                    ForEach(Array(displayedSongs.enumerated()), id: \.offset) { idx, song in
                        Button {
                            play(song, context: displayedSongs)
                        } label: {
                            PlaylistRow(song: song, showsArtwork: true, horizontalPadding: rowHorizontalPadding)
                                .contentShape(Rectangle())
                                .songRowAccessibility(song: song) {
                                    play(song, context: displayedSongs)
                                }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .accessibilityIdentifier("PlaylistDetail.song.\(song.id)")
                        if idx < displayedSongs.count - 1 {
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
