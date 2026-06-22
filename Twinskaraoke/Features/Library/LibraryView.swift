import Combine
import Foundation
import SwiftUI

@MainActor
final class PlaylistSongCountStore: ObservableObject {
    static let shared = PlaylistSongCountStore()

    @Published private var resolvedCounts: [String: Int] = [:]
    private var loadingIDs: Set<String> = []

    func displayedCount(for playlist: Playlist) -> Int? {
        if let resolved = resolvedCounts[playlist.id], resolved > 0 {
            return resolved
        }
        let embeddedCount = playlist.songListDTOs?.count ?? 0
        if embeddedCount > 0 {
            return max(playlist.songCount, embeddedCount)
        }
        return playlist.songCount > 0 ? playlist.songCount : nil
    }

    func loadIfNeeded(for playlist: Playlist) {
        guard !playlist.isFavorites, !playlist.isPersonal else { return }
        guard playlist.songCount == 0 else { return }
        guard resolvedCounts[playlist.id] == nil else { return }
        guard !loadingIDs.contains(playlist.id) else { return }

        Task {
            loadingIDs.insert(playlist.id)
            let count: Int?
            do {
                count = try await KaraokeAPIClient.playlistSongCount(id: playlist.id)
            } catch {
                count = nil
            }

            loadingIDs.remove(playlist.id)
            if let count, count > 0 {
                resolvedCounts[playlist.id] = count
            }
        }
    }
}

struct PlaylistSongCountLabel: View {
    let playlist: Playlist
    var fallbackText: String?

    @ObservedObject private var countStore = PlaylistSongCountStore.shared

    private var labelText: String? {
        if let count = countStore.displayedCount(for: playlist) {
            return SongCountText.songs(count)
        }
        return fallbackText
    }

    var body: some View {
        Group {
            if let labelText {
                Text(labelText)
            }
        }
        .task(id: playlist.id) {
            countStore.loadIfNeeded(for: playlist)
        }
    }
}

struct LibraryView: View {
    @StateObject var viewModel = PlaylistsViewModel()
    @StateObject private var recentSongsViewModel = LibrarySongsViewModel()
    @ObservedObject private var savedStore = SavedPlaylistsStore.shared
    @ObservedObject private var addedTracker = RecentlyAddedTracker.shared
    @ObservedObject private var favorites = FavoritesManager.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var showCreateSheet = false
    @State private var path = NavigationPath()
    let cols = AM.Layout.playlistGridColumns

    private var usesCompactToolbar: Bool {
        horizontalSizeClass == .compact
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
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
            .refreshable {
                refreshLibrary()
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
                viewModel.fetchFavoriteSongs()
            }
            .animation(
                reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
                value: recentlyAddedSongs.map(\.id)
            )
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
                destination: PlaylistsGridScreen(viewModel: viewModel)
            )
            libraryLink(icon: "music.mic", title: "Artists", destination: ArtistsView())
            libraryLink(icon: "music.note", title: "Songs", destination: LibrarySongsView())
            libraryLink(
                icon: "arrow.down.circle",
                title: "Downloaded",
                destination: DownloadedSongsView()
            )
            libraryLink(icon: "play.rectangle", title: "Video Gallery", destination: VideoGalleryView())
            libraryLink(icon: "paintpalette", title: "Art Gallery", destination: ArtGalleryView())
            libraryLink(
                icon: "shuffle",
                title: "Random Songs",
                destination: RandomSongsView(),
                showsDivider: false
            )
        }
    }

    private var librarySecondaryLinks: some View {
        EmptyView()
    }

    private var librarySecondaryLinksContent: some View {
        EmptyView()
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

    private func refreshLibrary() {
        AppHaptic.selection.play()
        favorites.loadIfNeeded()
        viewModel.fetchPlaylists()
        viewModel.fetchFavoriteSongs()
        recentSongsViewModel.refresh()
    }
}

private struct LibraryToolbarActions: View {
    var compact = false
    let onCreatePlaylist: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        ToolbarCapsuleMenu(accessibilityLabel: "Library Actions") {
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

enum LibrarySongSort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case artist
    case duration

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .title: "Title"
        case .artist: "Artist"
        case .duration: "Duration"
        }
    }

    var symbol: String {
        switch self {
        case .recentlyAdded: "clock"
        case .title: "textformat"
        case .artist: "person"
        case .duration: "timer"
        }
    }
}

@MainActor
final class LibrarySongsViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var sort: LibrarySongSort = .recentlyAdded
    @Published var searchText = ""
    private var hasLoaded = false
    private var canLoadMore = true
    private var page = 1
    private var requestToken = 0
    private let pageSize = 40

    var displayedSongs: [Song] {
        let sorted: [Song] = switch sort {
        case .recentlyAdded:
            songs
        case .title:
            songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            songs.sorted {
                $0.displayArtist.localizedStandardCompare($1.displayArtist) == .orderedAscending
            }
        case .duration:
            songs.sorted { $0.duration < $1.duration }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { song in
            song.title.localizedCaseInsensitiveContains(query)
                || song.displayArtist.localizedCaseInsensitiveContains(query)
                || song.displayTitle.localizedCaseInsensitiveContains(query)
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        fetch(page: 1, replace: true)
    }

    func refresh() {
        hasLoaded = false
        canLoadMore = true
        fetch(page: 1, replace: true)
    }

    func loadMoreIfNeeded(current: Song) {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let visible = displayedSongs
        guard let index = visible.firstIndex(where: { $0.id == current.id }) else { return }
        guard index >= visible.count - 8 else { return }
        fetch(page: page + 1, replace: false)
    }

    func loadMore() {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        fetch(page: page + 1, replace: false)
    }

    private func fetch(page: Int, replace: Bool) {
        guard canLoadMore || replace else { return }
        guard !isLoading, !isLoadingMore else { return }
        guard let url = URL(string: "\(StorageHost.api)/api/songs") else { return }

        requestToken += 1
        let token = requestToken
        if replace {
            isLoading = songs.isEmpty
        } else {
            isLoadingMore = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaults.standard.string(forKey: "nk.token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        GuestIdentity.applyIfNeeded(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "page": page,
            "pageSize": pageSize,
            "search": "",
            "sortBy": "CreatedAt",
            "sortDescending": true,
        ])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self, data, response, error, page, replace, token] in
                self?.applyResponse(
                    data,
                    response: response,
                    error: error,
                    page: page,
                    replace: replace,
                    token: token
                )
            }
        }.resume()
    }

    private func applyResponse(
        _ data: Data?,
        response: URLResponse?,
        error: Error?,
        page: Int,
        replace: Bool,
        token: Int
    ) {
        guard token == requestToken else { return }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        if let error {
            DebugLogger.log("Library songs fetch failed: \(error.localizedDescription)", category: .network)
            return
        }
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            DebugLogger.log("Library songs HTTP \(http.statusCode)", category: .network)
            return
        }

        let decoded = Self.decodeSongs(from: data)
        let filtered = decoded.filter {
            !$0.title.localizedCaseInsensitiveContains("Temporary Stream Audio")
        }
        let pageSongs = filtered.isEmpty ? decoded : filtered

        if replace {
            songs = pageSongs
            hasLoaded = true
        } else {
            let existing = Set(songs.map(\.id))
            songs += pageSongs.filter { !existing.contains($0.id) }
        }

        canLoadMore = pageSongs.count == pageSize
        if !pageSongs.isEmpty || replace {
            self.page = page
        }
        ArtworkPrefetcher.shared.prefetchSongs(
            Array(pageSongs.prefix(18)),
            limit: 18,
            reason: replace ? "library songs initial" : "library songs page"
        )
    }

    private static func decodeSongs(from data: Data?) -> [Song] {
        guard let data else { return [] }
        if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return decoded.items
        }
        return SongPayloadDecoder.decodeSongs(from: data) ?? []
    }
}

struct LibrarySongsView: View {
    @StateObject private var viewModel = LibrarySongsViewModel()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84)
    }

    var body: some View {
        let songs = viewModel.displayedSongs
        let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let showsRowArtwork = songs.count <= 200
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
                            SongRow(song: song, size: .regular, showsArtwork: showsRowArtwork)
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
            viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onChange(of: songs.map(\.id)) { _, _ in
            ArtworkPrefetcher.shared.prefetchSongs(
                Array(songs.prefix(18)),
                limit: 18,
                reason: "library visible songs"
            )
        }
        .animation(listAnimation, value: songs.map(\.id))
        .animation(listAnimation, value: viewModel.sort)
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
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
            Button {
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
        }
    }

    private func emptyState(isSearching: Bool) -> some View {
        MusicEmptyState(
            title: isSearching ? "No Results" : "No Songs",
            message: isSearching
                ? "Try another song or artist."
                : "Songs you load from Twins Karaoke will appear here."
        )
        .frame(maxWidth: .infinity, minHeight: 360)
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
    @ObservedObject var viewModel: PlaylistsViewModel
    @ObservedObject var savedStore: SavedPlaylistsStore = .shared
    @ObservedObject private var userManager = UserPlaylistsManager.shared
    @ObservedObject private var favorites = FavoritesManager.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var showCreateSheet = false
    @State private var searchText = ""
    let cols = AM.Layout.playlistGridColumns

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var isLoggedIn: Bool {
        UserDefaults.standard.string(forKey: "nk.token") != nil
    }

    private var combinedPlaylists: [Playlist] {
        let userConverted = userManager.playlists.map { $0.asPlaylist() }
        let all = viewModel.allPlaylists(saved: savedStore.playlists)
        let existingIDs = Set(all.map(\.id))
        let uniqueUser = userConverted.filter { !existingIDs.contains($0.id) }
        return uniqueUser + all
    }

    private var displayedPlaylists: [Playlist] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return combinedPlaylists }
        return combinedPlaylists.filter { playlist in
            playlist.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let all = combinedPlaylists
        let displayed = displayedPlaylists
        ScrollView {
            Group {
                if viewModel.isLoading, userManager.isLoading, all.isEmpty {
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
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                PlaylistGridCell(playlist: playlist)
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
            viewModel.fetchFavoriteSongs()
        }
        .animation(
            reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
            value: displayed.map(\.id)
        )
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistSheet()
        }
    }
}

struct PlaylistGridCell: View {
    let playlist: Playlist
    var width: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.s) {
            artwork
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
                .amShadow(AM.Shadow.card)
            Text(playlist.name)
                .font(AM.Font.tileTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !playlist.isFavorites {
                PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
                    .font(AM.Font.tileCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
        VStack(alignment: .leading, spacing: 12) {
            PlaylistArtwork(playlist: playlist, cornerRadius: 12)
                .frame(width: 220, height: 220)
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
        .padding(16)
        .frame(width: 252, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PlaylistsSkeletonView: View {
    var body: some View {
        CenteredLoadingView(label: "Loading playlists")
    }
}
