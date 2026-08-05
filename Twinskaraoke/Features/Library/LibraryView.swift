import Foundation
import SwiftUI

struct PlaylistSongCountLabel: View {
    let playlist: Playlist
    var fallbackText: String?
    var prefersDetailCount = true

    private let countStore = PlaylistSongCountStore.shared

    private var labelText: String? {
        if let count = countStore.displayedCount(
            for: playlist,
            prefersDetailCount: prefersDetailCount
        ) {
            return SongCountText.songs(count)
        }
        return fallbackText
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            if let labelText {
                Text(labelText)
            }
        }
        .task(id: playlist.id) {
            countStore.loadIfNeeded(
                for: playlist,
                forceDetailCount: prefersDetailCount
                    && PlaylistSongCountStore.needsDetailCount(
                        for: playlist,
                        isSaved: SavedPlaylistsStore.shared.isSaved(playlist)
                    )
            )
        }
    }
}

struct LibraryView: View {
    /// Owned here, on the view that owns the NavigationStack, and passed down.
    ///
    /// Apple's guidance for the zoom transition is that the namespace belongs to
    /// the stack root rather than to a pushed screen — see the discussion under
    /// developer.apple.com/forums/thread/810944. It previously lived on
    /// PlaylistsGridScreen, one level below the stack.
    @Namespace private var zoomNamespace
    @State var viewModel = PlaylistsViewModel()
    @State private var recentSongsViewModel = LibrarySongsViewModel()
    private let savedStore = SavedPlaylistsStore.shared
    private let favorites = FavoritesManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showCreateSheet = false
    @State private var path = NavigationPath()
    @State private var favoritesRefreshTask: Task<Void, Never>?

    private var usesCompactToolbar: Bool {
        horizontalSizeClass == .compact
    }


    var body: some View {
        let recentlyAddedSongs = Array(recentSongsViewModel.songs.prefix(12))
        NavigationStack(path: $path) {
            GeometryReader { proxy in
                ScrollView {
                    libraryOverview(recentlyAddedSongs: recentlyAddedSongs, availableWidth: proxy.size.width)
                        .padding(.top, AM.Spacing.s)
                        .padding(.bottom, AM.Spacing.l)
                }
                .scrollIndicators(.hidden)
                .smoothScrolling()
                .tabBarScrollInset()
                .musicScreenBackground()
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LibraryToolbarActions(
                        compact: usesCompactToolbar,
                        onCreatePlaylist: {
                            AppHaptic.selection.play()
                            showCreateSheet = true
                        },
                        onRefresh: refreshLibrary
                    )
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton()
                }
            }
            // `refreshLibraryAndWait()` plays the trigger tick itself.
            .refreshable {
                await refreshLibraryAndWait()
            }
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .onAppear {
                favorites.loadIfNeeded()
                viewModel.fetchPlaylists()
                viewModel.fetchFavoriteSongs()
                recentSongsViewModel.loadIfNeeded()
            }
            .onChange(of: favorites.favoriteIDs) { _, _ in
                // Every star tap anywhere in the app fires this; LibraryView is a
                // tab root that is always alive, so coalesce rapid toggles into a
                // single refetch instead of fetching the whole list per tap.
                favoritesRefreshTask?.cancel()
                favoritesRefreshTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    viewModel.fetchFavoriteSongs(force: true)
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreatePlaylistSheet()
            }
        }
    }

    @ViewBuilder
    private func libraryOverview(recentlyAddedSongs: [Song], availableWidth: CGFloat) -> some View {
        if AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        ) {
            wideLibraryOverview(recentlyAddedSongs: recentlyAddedSongs)
        } else {
            compactLibraryOverview(recentlyAddedSongs: recentlyAddedSongs)
        }
    }

    private func compactLibraryOverview(recentlyAddedSongs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
            libraryPrimaryLinks

            if !recentlyAddedSongs.isEmpty {
                RecentlyAddedSection(songs: recentlyAddedSongs)
            }
        }
    }

    private func wideLibraryOverview(recentlyAddedSongs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
            if let featuredPlaylist = featuredWidePlaylist {
                WideLibraryHero(
                    playlist: featuredPlaylist,
                    songs: featuredPlaylist.songListDTOs ?? viewModel.favoriteSongs
                )
            }

            HStack(alignment: .top, spacing: AM.Spacing.xxl) {
                VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
                    LibraryOverviewGroup(title: "Library") {
                        libraryPrimaryLinksContent
                    }
                }
                .frame(
                    minWidth: AM.Layout.wideInspectorWidth,
                    idealWidth: AM.Layout.wideInspectorWidth,
                    maxWidth: 400
                )

                if !recentlyAddedSongs.isEmpty {
                    RecentlyAddedSection(songs: recentlyAddedSongs, horizontalPadding: 0, headerHorizontalPadding: 0)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: AM.Layout.wideContentMaxWidth, alignment: .topLeading)
            .padding(.horizontal, AM.Spacing.screenMargin)
            .accessibilityIdentifier("Library.WideOverview")
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var featuredWidePlaylist: Playlist? {
        let all = viewModel.allPlaylists(saved: savedStore.playlists)
        if let favoritesPlaylist = all.first(where: { $0.isFavorites }) {
            return favoritesPlaylist
        }
        if let saved = savedStore.playlists.first {
            return saved
        }
        return all.first
    }

    private var libraryPrimaryLinks: some View {
        libraryPrimaryLinksContent
            .padding(.horizontal, AM.Spacing.screenMargin)
    }

    private var libraryPrimaryLinksContent: some View {
        VStack(spacing: 0) {
            libraryLink(
                icon: "music.note.list",
                title: "Playlists",
                destination: PlaylistsGridScreen(viewModel: viewModel, zoomNamespace: zoomNamespace)
            )
            libraryLink(icon: "music.mic", title: "Artists", destination: ArtistsView())
            libraryLink(icon: "music.note", title: "Songs", destination: LibrarySongsView())
            libraryLink(
                icon: "arrow.down.circle",
                title: "Downloaded",
                destination: DownloadedSongsView()
            )
            libraryLink(
                icon: "arrow.up.circle",
                title: "Uploaded",
                destination: UploadedSongsView()
            )
            libraryLink(icon: "paintpalette", title: "Art Gallery", destination: ArtGalleryView())
            libraryLink(icon: "play.rectangle", title: "Video Gallery", destination: VideoGalleryView())
            libraryLink(
                icon: "shuffle",
                title: "Random Songs",
                destination: RandomSongsView(),
                showsDivider: false
            )
        }
    }

    @ViewBuilder
    private func libraryLink(
        icon: String,
        title: String,
        subtitle: String? = nil,
        destination: some View,
        showsDivider: Bool = true
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            LibraryRow(icon: icon, color: .appAccent, title: title, subtitle: subtitle)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))

        if showsDivider {
            LibraryLinkSeparator()
        }
    }

    /// Fire-and-forget variant for the toolbar button, which has no way to show
    /// progress and so has nothing to wait on.
    private func refreshLibrary() {
        AppHaptic.selection.play()
        favorites.loadIfNeeded()
        viewModel.fetchPlaylists(force: true)
        viewModel.fetchFavoriteSongs(force: true)
        recentSongsViewModel.refresh()
    }

    /// Awaitable variant for pull-to-refresh; keeps the refresh spinner alive
    /// until every library section has actually finished loading.
    private func refreshLibraryAndWait() async {
        AppHaptic.selection.play()
        favorites.loadIfNeeded()
        async let playlists: Void = viewModel.refreshAll()
        async let recents: Void = recentSongsViewModel.refreshSongs()
        _ = await (playlists, recents)
    }
}

private struct LibraryToolbarActions: View {
    var compact = false
    let onCreatePlaylist: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        ToolbarCapsuleMenu(accessibilityLabel: "More Library Actions") {
            Button(action: onCreatePlaylist) {
                Label("New Playlist", systemImage: "text.badge.plus")
            }
            Button(action: onRefresh) {
                Label("Refresh Library", systemImage: "arrow.clockwise")
            }
        }
    }
}

private struct LibraryLinkSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.appDivider)
            .frame(height: 0.5)
            .padding(.leading, 44)
    }
}

private struct LibraryOverviewGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.s) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, AM.Spacing.s)

            content
                .padding(.horizontal, 0)
        }
    }
}

private struct WideLibraryHero: View {
    let playlist: Playlist
    let songs: [Song]

    var body: some View {
        HStack(alignment: .center, spacing: AM.Spacing.xxl) {
            PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.hero)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
                .amShadow(AM.Shadow.heroPlaying)

            VStack(alignment: .leading, spacing: AM.Spacing.l) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(playlist.isFavorites ? "Favourite Songs" : "Featured Playlist")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(playlist.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)
                    PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: AM.Spacing.m) {
                    Button {
                        if let first = playableSongs.first {
                            AppHaptic.selection.play()
                            AudioPlayerManager.shared.playInOrder(song: first, context: playableSongs)
                        }
                    } label: {
                        LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
                    }
                    .disabled(playableSongs.isEmpty)
                    .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))

                    Button {
                        AppHaptic.selection.play()
                        AudioPlayerManager.shared.playShuffled(from: playableSongs)
                    } label: {
                        LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
                    }
                    .disabled(playableSongs.isEmpty)
                    .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))

                    NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                        Image(systemName: "chevron.right")
                            .font(AM.Font.chevron)
                            .foregroundStyle(Color.appAccent)
                            .frame(width: 46, height: 46)
                            .background(Color.appControlInactiveFill, in: Circle())
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
                    .accessibilityLabel("Open \(playlist.name)")
                    .accessibilityHint("Shows playlist details.")
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(AM.Spacing.xl)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
                .strokeBorder(Color.appDivider.opacity(0.7), lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Library.WideHero")
    }

    private var playableSongs: [Song] {
        let direct = playlist.songListDTOs ?? []
        return direct.isEmpty ? songs : direct
    }
}

struct LibrarySongsView: View {
    @State private var viewModel = LibrarySongsViewModel()
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var prefetchedIDs: [String] = []

    var body: some View {
        let songs = viewModel.displayedSongs
        let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        List {
            if viewModel.isLoading, songs.isEmpty {
                skeletonRows
            } else if songs.isEmpty {
                emptyState(isSearching: isSearching)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    actionButtons(songs: songs)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(songs) { song in
                        Button {
                            play(song, context: songs)
                        } label: {
                            SongRow(song: song, size: .regular, showsArtwork: true)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .songRowAccessibility(song: song) {
                                    play(song, context: songs)
                                }
                        }
                        .id(song.id)
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                        .onAppear {
                            viewModel.loadMoreIfNeeded(current: song)
                        }
                    }
                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.regular)
                            Spacer()
                        }
                        .frame(height: 44)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Songs"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }
        }
        .refreshable {
            AppHaptic.selection.play()
            await viewModel.refreshSongs()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        // Diffing on displayedSongs (Equatable) avoids allocating the prefix
        // id array on every body eval; it only builds when the list changes.
        .onChange(of: viewModel.displayedSongs) { _, newSongs in
            let visible = Array(newSongs.prefix(18))
            let ids = visible.map(\.id)
            guard ids != prefetchedIDs else { return }
            prefetchedIDs = ids
            ArtworkPrefetcher.shared.prefetchSongs(
                visible,
                limit: 18,
                reason: "library visible songs",
                variant: .row
            )
        }
        .onDisappear {
            ArtworkPrefetcher.shared.cancel(reason: "library visible songs")
        }
    }

    private func play(_ song: Song, context: [Song]) {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: context)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LibrarySongSort.allCases) { sort in
                Button {
                    AppHaptic.selection.play()
                    viewModel.sort = sort
                } label: {
                    Label(sort.title, systemImage: viewModel.sort == sort ? "checkmark" : sort.symbol)
                }
            }
        } label: {
            Label("Sort Songs", systemImage: "arrow.up.arrow.down")
                .font(.headline)
                .foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .labelStyle(.iconOnly)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72, haptic: .selection))
    }

    private func actionButtons(songs: [Song]) -> some View {
        HStack(spacing: 12) {
            Button {
                if let first = songs.first {
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .commit))
            Button {
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .commit))
        }
    }

    private func emptyState(isSearching: Bool) -> some View {
        VStack(spacing: AM.Spacing.l) {
            MusicEmptyState(title: emptyTitle(isSearching: isSearching), message: emptyMessage(isSearching: isSearching))

            if viewModel.loadFailed, !isSearching {
                MusicEmptyActionButton(title: "Try Again") {
                    AppHaptic.selection.play()
                    viewModel.refresh()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func emptyTitle(isSearching: Bool) -> String {
        if isSearching { return "No Results" }
        if viewModel.loadFailed { return "Couldn't Load Songs" }
        return "No Songs"
    }

    private func emptyMessage(isSearching: Bool) -> String {
        if isSearching { return "Try another song or artist." }
        if viewModel.loadFailed { return "Check your connection and try again." }
        return "Songs you load from Twins Karaoke will appear here."
    }

    private var skeletonRows: some View {
        CenteredLoadingView()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

struct LibraryRow: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AM.Font.rowTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(AM.Font.tileCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
    }
}

struct PlaylistListRow: View {
    let playlist: Playlist
    var body: some View {
        HStack(spacing: 12) {
            PlaylistArtwork(playlist: playlist, cornerRadius: 6)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.subheadline)
                    .lineLimit(1)
                PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct PlaylistsGridScreen: View {
    let viewModel: PlaylistsViewModel
    /// Supplied by LibraryView, which owns the NavigationStack.
    let zoomNamespace: Namespace.ID
    private let userManager = UserPlaylistsManager.shared
    private let favorites = FavoritesManager.shared
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var showCreateSheet = false
    @State private var searchText = ""
    @State private var favoritesRefreshTask: Task<Void, Never>?
    let cols = AM.Layout.playlistGridColumns


    private var isLoggedIn: Bool {
        CredentialStore.isAuthenticated
    }

    var body: some View {
        let all = viewModel.combinedPlaylists
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayed = query.isEmpty ? all : all.filter { playlist in
            playlist.name.localizedCaseInsensitiveContains(query)
        }
        ScrollView {
            Group {
                if (viewModel.isLoading || userManager.isLoading), all.isEmpty {
                    PlaylistsSkeletonView()
                } else if displayed.isEmpty {
                    MusicEmptyState(
                        title: searchText.isEmpty ? "No Playlists" : "No Results",
                        message: searchText.isEmpty
                            ? "Playlists you add will appear here."
                            : "Try another playlist name."
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .padding(.top, 48)
                } else {
                    LazyVGrid(columns: cols, spacing: AM.Spacing.l) {
                        ForEach(displayed) { playlist in
                            ZoomNavigationLink(id: playlist.id, in: zoomNamespace) {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                PlaylistGridCell(
                                    playlist: playlist,
                                    prefersDetailCount: true
                                )
                            }
                            .buttonStyle(PressableButtonStyle())
                            .contextMenu {
                                PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
                            } preview: {
                                PlaylistContextPreview(playlist: playlist)
                            }
                        }
                    }
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .padding(.vertical, AM.Spacing.m)
                }
            }
        }
        .smoothScrolling()
        .navigationTitle("Playlists")
        // Inline, matching PlaylistListView. A large title has to collapse into
        // the bar when this screen pushes, and the zoom transition leaves the
        // screen on display while that happens — so the title visibly slid up
        // on open and sprang back on return. Nothing to collapse, nothing to
        // animate. PlaylistListView pushes the same detail view and never
        // showed the bounce, because it was already inline.
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Playlists"
        )
        .toolbar {
            if isLoggedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarIconButton(
                        systemImage: "plus",
                        accessibilityLabel: "New Playlist",
                        foregroundColor: .appAccent
                    ) {
                        showCreateSheet = true
                    }
                }
            }
        }
        .task { userManager.loadIfNeeded() }
        .onChange(of: favorites.favoriteIDs) { _, _ in
            favoritesRefreshTask?.cancel()
            favoritesRefreshTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                viewModel.fetchFavoriteSongs(force: true)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistSheet()
        }
    }
}

struct PlaylistGridCell: View {
    let playlist: Playlist
    var width: CGFloat?
    var prefersDetailCount = true
    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.s) {
            artwork
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
            Text(playlist.name)
                .font(AM.Font.tileTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
            PlaylistSongCountLabel(
                playlist: playlist,
                fallbackText: prefersDetailCount ? nil : "Playlist",
                prefersDetailCount: prefersDetailCount
            )
                .font(AM.Font.tileCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    @ViewBuilder private var artwork: some View {
        if let width {
            PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.card)
                .frame(width: width, height: width)
        } else {
            PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.card)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }
}

struct RecentlyAddedSection: View {
    let songs: [Song]
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin
    var headerHorizontalPadding: CGFloat = AM.Spacing.screenMargin
    private let cols = AM.Layout.songGridColumns
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recently Added")
                .font(AM.Font.sectionHeader)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, headerHorizontalPadding)
                .padding(.top, 2)
            LazyVGrid(columns: cols, spacing: 22) {
                ForEach(songs) { song in
                    MusicGridCard(song: song, context: songs, fillsWidth: true)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlaylistContextPreview: View {
    let playlist: Playlist

    var body: some View {
        ContextPreviewCard {
            PlaylistArtwork(playlist: playlist, cornerRadius: 12)
                .frame(width: 220, height: 220)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(AM.Font.tileTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
                    .font(AM.Font.tileCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct PlaylistsSkeletonView: View {
    var body: some View {
        CenteredLoadingView(label: "Loading playlists")
    }
}
