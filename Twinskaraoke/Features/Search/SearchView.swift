import SwiftUI

struct SearchView: View {
    @State var viewModel = SearchViewModel()
    // Owned here rather than by the browse page, which is torn down whenever
    // results replace it. Owned there, clearing a search rebuilt all three and
    // fetched genres, the chart and public playlists again, and the page came
    // back scrolled to the top.
    @State private var genresVM = GenresViewModel()
    @State private var topChartVM = TopChartViewModel()
    @State private var publicPlaylistsVM = PublicPlaylistsViewModel()
    private let recentSearches = RecentSearchesStore.shared

    private let playback = PlaybackRowState.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var pendingSongID: String?
    @State private var playbackTask: Task<Void, Never>?

    private var subtleStateTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private var resultsEmptyTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }


    private func usesWideCanvas(availableWidth: CGFloat) -> Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }

    private func resultsMaxWidth(availableWidth: CGFloat) -> CGFloat {
        usesWideCanvas(availableWidth: availableWidth) ? 780 : .infinity
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    // Always mounted, and only hidden while another state is on
                    // screen. Swapped out for the results list, the browse page
                    // lost its scroll position with every search.
                    SearchLandingView(
                        recentSearches: recentSearches,
                        pendingSongID: pendingSongID,
                        onPlay: { song in playSelection(song, context: [song]) }
                    ) {
                        BrowseCategoriesView(
                            availableWidth: proxy.size.width,
                            genresVM: genresVM,
                            topChartVM: topChartVM,
                            publicPlaylistsVM: publicPlaylistsVM
                        )
                    }
                    .opacity(showsLanding ? 1 : 0)
                    .allowsHitTesting(showsLanding)
                    .accessibilityHidden(!showsLanding)

                    if viewModel.isSearching, viewModel.results.isEmpty {
                        SearchResultsLoadingView()
                            .transition(.opacity)
                    } else if let errorMessage = viewModel.searchErrorMessage,
                              viewModel.results.isEmpty,
                              viewModel.hasActiveQuery
                    {
                        SearchErrorStateView(message: errorMessage) {
                            viewModel.retrySearch()
                        }
                        .transition(subtleStateTransition)
                    } else if viewModel.results.isEmpty, viewModel.hasActiveQuery {
                        SearchNoResultsStateView(query: viewModel.searchText)
                            .transition(resultsEmptyTransition)
                    } else if !viewModel.results.isEmpty {
                        List {
                            SearchResultsSummaryHeader(
                                query: viewModel.searchText,
                                resultCount: viewModel.totalResultCount ?? viewModel.results.count
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)

                            ForEach(viewModel.results) { song in
                                Button {
                                    playSelection(song, context: viewModel.results)
                                } label: {
                                    SearchResultRow(song: song, isPending: pendingSongID == song.id) {
                                        playSelection(song, context: viewModel.results)
                                    }
                                }
                                .disabled(pendingSongID != nil)
                                .buttonStyle(PressableButtonStyle())
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    viewModel.loadMoreIfNeeded(after: song)
                                }
                            }

                            if viewModel.isLoadingMore || viewModel.loadMoreFailed {
                                SearchResultsPagingFooter(isLoading: viewModel.isLoadingMore) {
                                    viewModel.retryLoadMore()
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .smoothScrolling()
                        .scrollIndicators(.hidden)
                        .frame(maxWidth: resultsMaxWidth(availableWidth: proxy.size.width))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("SearchResults.List")
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : AppMotion.quick, value: showsLanding)
                .musicScreenBackground()
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton()
                }
            }
            .searchable(
                text: $viewModel.searchText,
                prompt: "Songs, Artists, Lyrics, and More"
            )
            .onSubmit(of: .search) {
                viewModel.search(viewModel.searchText)
            }
            .onChange(of: playback.currentSongID) { _, currentSongID in
                guard currentSongID == pendingSongID else { return }
                pendingSongID = nil
            }
            .onChange(of: Array(viewModel.results.prefix(18)).map(\.id)) { _, _ in
                ArtworkPrefetcher.shared.prefetchSongs(
                    Array(viewModel.results.prefix(18)),
                    limit: 18,
                    reason: "search results",
                    variant: .row
                )
            }
            .onDisappear {
                playbackTask?.cancel()
                playbackTask = nil
                pendingSongID = nil
                ArtworkPrefetcher.shared.cancel(reason: "search results")
            }
        }
    }

    /// No query, and nothing loading or found for one.
    private var showsLanding: Bool {
        !viewModel.hasActiveQuery && viewModel.results.isEmpty && !viewModel.isSearching
    }

    private func playSelection(_ song: Song, context: [Song]) {
        guard pendingSongID == nil else { return }
        recentSearches.record(song)
        guard playback.currentSongID != song.id else { return }
        AppHaptic.selection.play()
        pendingSongID = song.id
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            AudioPlayerManager.shared.play(song: song, context: context)
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, pendingSongID == song.id else { return }
            pendingSongID = nil
        }
    }
}

/// The last row while the next page of results is loading, or the way to ask
/// for it again when it failed. Failing quietly would leave the list looking
/// complete when it is not.
private struct SearchResultsPagingFooter: View {
    let isLoading: Bool
    let onRetry: () -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .accessibilityLabel("Loading more results")
            } else {
                VStack(spacing: 8) {
                    Text("More results couldn’t be loaded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try Again", action: onRetry)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .padding(.vertical, 8)
    }
}

private struct SearchResultsSummaryHeader: View {
    let query: String
    let resultCount: Int

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Songs")
                    .font(AM.Font.sectionHeader)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(resultCountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !trimmedQuery.isEmpty {
                Text("Results for \"\(trimmedQuery)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var resultCountText: String {
        resultCount == 1 ? String(localized: "1 song") : String(localized: "\(resultCount) songs")
    }
}

/// What Search shows before there is a query: the songs recently picked from
/// results while the field is open, as Apple Music does, and the browse page
/// otherwise.
private struct SearchLandingView<Browse: View>: View {
    let recentSearches: RecentSearchesStore
    let pendingSongID: String?
    let onPlay: (Song) -> Void
    @ViewBuilder let browse: () -> Browse
    @Environment(\.isSearching) private var isSearching
    @Environment(\.appReduceMotion) private var reduceMotion

    private var showsRecents: Bool {
        isSearching && !recentSearches.songs.isEmpty
    }

    var body: some View {
        ZStack {
            // Kept mounted underneath so its shelves and scroll position
            // survive opening and closing the field.
            browse()
                .opacity(showsRecents ? 0 : 1)
                .allowsHitTesting(!showsRecents)
                .accessibilityHidden(showsRecents)
            if showsRecents {
                RecentSearchesList(
                    songs: recentSearches.songs,
                    pendingSongID: pendingSongID,
                    onPlay: onPlay,
                    onRemove: { recentSearches.remove($0) },
                    onClear: { recentSearches.clear() }
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : AppMotion.quick, value: showsRecents)
    }
}

private struct RecentSearchesList: View {
    let songs: [Song]
    let pendingSongID: String?
    let onPlay: (Song) -> Void
    let onRemove: (Song) -> Void
    let onClear: () -> Void

    var body: some View {
        List {
            HStack(alignment: .firstTextBaseline) {
                Text("Recently Searched")
                    .font(AM.Font.sectionHeader)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button("Clear") {
                    AppHaptic.dismiss.play()
                    onClear()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appAccent)
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear Recent Searches")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)

            ForEach(songs) { song in
                Button {
                    onPlay(song)
                } label: {
                    SearchResultRow(song: song, isPending: pendingSongID == song.id) {
                        onPlay(song)
                    }
                }
                .disabled(pendingSongID != nil)
                .buttonStyle(PressableButtonStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        AppHaptic.dismiss.play()
                        onRemove(song)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .smoothScrolling()
        .musicScreenBackground()
        .accessibilityIdentifier("Search.RecentlySearched")
    }
}

private struct BrowseCategoriesView: View {
    let availableWidth: CGFloat
    let genresVM: GenresViewModel
    let topChartVM: TopChartViewModel
    let publicPlaylistsVM: PublicPlaylistsViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let genres: [(String, [Color])] = [
        (
            "Pop", [Color(red: 0.90, green: 0.20, blue: 0.55), Color(red: 0.40, green: 0.05, blue: 0.30)]
        ),
        (
            "Hip-Hop",
            [Color(red: 0.60, green: 0.30, blue: 0.95), Color(red: 0.20, green: 0.05, blue: 0.45)]
        ),
        (
            "R&B", [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.45, green: 0.20, blue: 0.05)]
        ),
        (
            "Rock",
            [Color(red: 0.85, green: 0.20, blue: 0.20), Color(red: 0.30, green: 0.05, blue: 0.05)]
        ),
        (
            "Country",
            [Color(red: 0.85, green: 0.65, blue: 0.30), Color(red: 0.45, green: 0.25, blue: 0.05)]
        ),
        (
            "Electronic",
            [Color(red: 0.10, green: 0.75, blue: 0.85), Color(red: 0.05, green: 0.30, blue: 0.45)]
        ),
        (
            "Latin",
            [Color(red: 0.95, green: 0.35, blue: 0.20), Color(red: 0.45, green: 0.10, blue: 0.05)]
        ),
        (
            "K-Pop",
            [Color(red: 0.95, green: 0.45, blue: 0.75), Color(red: 0.40, green: 0.10, blue: 0.40)]
        ),
        (
            "Jazz",
            [Color(red: 0.60, green: 0.45, blue: 0.20), Color(red: 0.25, green: 0.15, blue: 0.05)]
        ),
        (
            "Classical",
            [Color(red: 0.40, green: 0.55, blue: 0.40), Color(red: 0.10, green: 0.25, blue: 0.15)]
        ),
        (
            "Reggae",
            [Color(red: 0.30, green: 0.65, blue: 0.30), Color(red: 0.10, green: 0.30, blue: 0.10)]
        ),
        (
            "Soundtracks",
            [Color(red: 0.45, green: 0.45, blue: 0.55), Color(red: 0.15, green: 0.15, blue: 0.25)]
        ),
    ]
    private var usesWideHighlights: Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }

    private var contentMaxWidth: CGFloat {
        usesWideHighlights ? AM.Layout.wideContentMaxWidth : .infinity
    }

    private var sectionHorizontalPadding: CGFloat {
        AM.Spacing.screenMargin
    }

    private var categoryColumns: [GridItem] {
        if horizontalSizeClass == .compact {
            return compactTwoColumns
        }
        return AM.Layout.adaptiveGridColumns(
            minimum: 178,
            spacing: AM.Spacing.m
        )
    }

    private var featuredColumns: [GridItem] {
        if horizontalSizeClass == .compact {
            return compactTwoColumns
        }
        return AM.Layout.adaptiveGridColumns(
            minimum: 232,
            spacing: AM.Spacing.m
        )
    }

    private var compactTwoColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: AM.Spacing.m, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: AM.Spacing.m, alignment: .top),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
                if usesWideHighlights {
                    wideBrowseBoard
                } else {
                    featuredSection
                    genresSection
                }
            }
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, AM.Spacing.s)
            .padding(.bottom, AM.Spacing.l)
        }
        .smoothScrolling()
        .musicScreenBackground()
        .scrollIndicators(.hidden)
        .refreshable {
            AppHaptic.selection.play()
            // `async let` so the three shelves reload concurrently; awaiting
            // them in sequence would make the spinner sit through three
            // round trips instead of one.
            async let genres: Void = genresVM.refreshGenres()
            async let topChart: Void = topChartVM.refreshTopChart()
            async let playlists: Void = publicPlaylistsVM.refreshPublicPlaylists()
            _ = await (genres, topChart, playlists)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                publicPlaylistsVM.loadIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                publicPlaylistsVM.loadIfNeeded()
            }
            .onAppear {
            genresVM.loadIfNeeded()
            topChartVM.loadIfNeeded()
            publicPlaylistsVM.loadIfNeeded()
        }
    }

    private var wideHighlightsSection: some View {
        featuredSectionContent
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("SearchBrowse.WideHighlights")
    }

    private var wideBrowseBoard: some View {
        HStack(alignment: .top, spacing: AM.Spacing.xxl) {
            VStack(alignment: .leading, spacing: AM.Spacing.sectionHeaderGap) {
                AMSectionHeader(String(localized: "Featured"), horizontalPadding: 0)
                featuredGrid(horizontalPadding: 0)
            }
            .frame(width: 390, alignment: .topLeading)

            VStack(alignment: .leading, spacing: AM.Spacing.sectionHeaderGap) {
                AMSectionHeader(String(localized: "Genres"), horizontalPadding: 0)
                genresGridContent
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, sectionHorizontalPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SearchBrowse.WideHighlights")
    }

    private var featuredSection: some View {
        featuredSectionContent
    }

    private var featuredSectionContent: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.m) {
            AMSectionHeader(String(localized: "Featured"))
            featuredGrid
        }
        .accessibilityIdentifier("SearchBrowse.Featured")
    }

    private var featuredGrid: some View {
        featuredGrid(horizontalPadding: sectionHorizontalPadding)
    }

    private func featuredGrid(horizontalPadding: CGFloat) -> some View {
        LazyVGrid(columns: featuredColumns, spacing: AM.Spacing.m) {
            NavigationLink(
                destination: TopChartCollectionView(viewModel: topChartVM)
            ) {
                SearchFeaturedShortcutTile(
                    title: "Twinskaraoke Top 100",
                    gradient: [
                        Color.appAccent,
                        Color(red: 0.56, green: 0.02, blue: 0.12),
                    ],
                    artworkURL: topChartVM.songs.first?.imageURL
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
            .accessibilityLabel("Twinskaraoke Top 100")
            .accessibilityIdentifier("SearchCategory.TwinskaraokeTop100")
            .accessibilityValue("\(topChartVM.songs.count) songs")
            .accessibilityHint("Opens the Top 100 songs collection")

            NavigationLink(
                destination: PublicPlaylistsCollectionView(viewModel: publicPlaylistsVM)
            ) {
                SearchFeaturedShortcutTile(
                    title: String(localized: "Public Playlists"),
                    subtitle: publicPlaylistsVM.errorMessage ?? (publicPlaylistsVM.isLoadingMore && publicPlaylistsVM.playlists.isEmpty
                        ? String(localized: "Loading playlists…")
                        : publicPlaylistsVM.playlists.isEmpty ? String(localized: "Community mixes") : String(localized: "\(publicPlaylistsVM.playlists.count) playlists")),
                    gradient: [
                        Color(red: 0.19, green: 0.55, blue: 0.96),
                        Color(red: 0.12, green: 0.22, blue: 0.58),
                    ],
                    artworkURL: publicPlaylistsVM.playlists.first?.imageURL
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
            .accessibilityLabel("Public Playlists")
            .accessibilityIdentifier("SearchCategory.PublicPlaylists")
            .accessibilityValue("\(publicPlaylistsVM.playlists.count) playlists")
            .accessibilityHint("Opens public playlists")
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var genresSection: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.m) {
            AMSectionHeader(String(localized: "Genres"))
            genresGridContent
                .padding(.horizontal, sectionHorizontalPadding)
            if genresVM.isLoadingMore {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AM.Spacing.m)
            }
        }
    }

    @ViewBuilder
    private var genresGridContent: some View {
        if genresVM.isLoading, genresVM.genres.isEmpty {
            CenteredLoadingView(label: String(localized: "Loading categories"))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if genresVM.genres.isEmpty {
            MusicEmptyState(
                title: String(localized: "Genres Unavailable"),
                message: String(localized: "Pull down to refresh browse categories.")
            )
            .padding(.top, AM.Spacing.s)
            .transition(.opacity)
        } else {
            LazyVGrid(columns: categoryColumns, spacing: AM.Spacing.m) {
                ForEach(genresVM.genres) { genre in
                    let palette = paletteForGenre(genre.name)
                    NavigationLink(
                        destination: GenreDetailView(genre: genre, viewModel: genresVM, palette: palette)
                    ) {
                        CategoryTile(
                            title: genre.name,
                            gradient: palette,
                            artworkURL: genresVM.artworkURLs[genre.id]
                        )
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
                    .accessibilityLabel(genre.name)
                    .accessibilityIdentifier("SearchCategory.\(genre.name.accessibilitySlug)")
                    .accessibilityValue("\(genre.songCount) songs")
                    .accessibilityHint("Opens \(genre.name) songs")
                    .onAppear {
                        genresVM.loadMoreIfNeeded(current: genre)
                        genresVM.loadPreviewIfNeeded(for: genre)
                    }
                    .onDisappear { genresVM.cancelQueuedPreview(for: genre) }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func paletteForGenre(_ name: String) -> [Color] {
        if let match = genres.first(where: {
            $0.0.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return match.1
        }
        return genres[Self.stablePaletteIndex(for: name, count: genres.count)].1
    }

    /// FNV-1a over unicode scalars: stable across launches, unlike `hashValue`.
    private static func stablePaletteIndex(for name: String, count: Int) -> Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for scalar in name.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
    }
}

private struct TopChartCollectionView: View {
    let viewModel: TopChartViewModel

    var body: some View {
        BrowseSongCollectionView(
            title: "Twinskaraoke Top 100",
            songs: viewModel.songs
        )
        .task {
            viewModel.loadIfNeeded()
        }
    }
}

private struct PublicPlaylistsCollectionView: View {
    let viewModel: PublicPlaylistsViewModel

    var body: some View {
        PlaylistListView(
            // "Twinskaraoke Top 100" next door is a product name and stays as
            // typed; this one is a description and should translate.
            title: String(localized: "Public Playlists"),
            playlists: viewModel.playlists,
            apiURL: { startIndex, pageSize in
                viewModel.urlForList(startIndex: startIndex, pageSize: pageSize)
            }
        )
        .safeAreaInset(edge: .top) {
            if let message = viewModel.errorMessage {
                VStack {
                    Text(message).font(.footnote)
                    Button("Retry") { viewModel.loadIfNeeded() }
                }
                .padding()
            }
        }
        .refreshable { await viewModel.refreshPublicPlaylists() }
        .task {
            viewModel.loadIfNeeded()
        }
    }
}

struct GenreDetailView: View {
    let genre: GenreSummary
    let viewModel: GenresViewModel
    let palette: [Color]
    @State private var detailOwner = UUID()

    var body: some View {
        let loadedSongs = viewModel.allSongs[genre.id]
        Group {
            if loadedSongs == nil, !viewModel.failedDetailIDs.contains(genre.id) {
                GenreDetailLoadingView(genre: genre)
                    .transition(.opacity)
            } else {
                BrowseSongCollectionView(
                    title: genre.name,
                    songs: loadedSongs ?? []
                )
                .transition(.opacity)
            }
        }
        // Keyed on the purge generation, not the cache entry: a memory-warning
        // purge cancels in-flight detail tasks without changing allSongs, so a
        // nil-entry key would never change and the load would never restart.
        .task(id: viewModel.detailGeneration) {
            viewModel.retainDetail(genre.id, owner: detailOwner)
            viewModel.loadDetailIfNeeded(for: genre)
        }
        .onDisappear { viewModel.releaseDetail(owner: detailOwner) }
    }
}

private struct GenreDetailLoadingView: View {
    let genre: GenreSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MusicArtworkPlaceholder(cornerRadius: AM.Radius.hero)
                    .frame(width: 240, height: 240)
                    .amShadow(AM.Shadow.heroIdle)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text(genre.name)
                        .font(AM.Font.sectionHeader)
                        .multilineTextAlignment(.center)
                    Text("Loading songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                CenteredLoadingView(minHeight: 160, label: String(localized: "Loading \(genre.name) songs"))
            }
            .padding(.bottom, AM.Spacing.l)
        }
        .smoothScrolling()
        .accessibilityLabel("Loading \(genre.name) songs")
    }
}

struct SearchCategorySongCollectionView: View {
    let title: String
    let query: String
    @State private var loader: SearchCategorySongsViewModel
    @Environment(\.appReduceMotion) private var reduceMotion

    private var categoryStateAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }


    init(title: String, query: String) {
        self.title = title
        self.query = query
        _loader = State(initialValue: SearchCategorySongsViewModel(query: query))
    }

    var body: some View {
        Group {
            if !loader.hasLoaded || loader.isLoading, loader.songs.isEmpty {
                SearchCategoryLoadingView(title: title)
                    .transition(.opacity)
            } else if loader.songs.isEmpty {
                SearchCategoryEmptyView(message: loader.emptyStateMessage) {
                    loader.refresh()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                BrowseSongCollectionView(
                    title: title,
                    songs: loader.songs
                )
            }
        }
        .musicScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            AppHaptic.selection.play()
            await loader.refreshCategory()
        }
        .task {
            loader.loadIfNeeded()
        }
        .animation(categoryStateAnimation, value: loader.isLoading)
    }
}

private struct SearchResultsLoadingView: View {
    var body: some View {
        CenteredLoadingView(label: String(localized: "Searching songs"))
    }
}

private struct SearchErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        SearchRecoveryStateView(
            title: String(localized: "Search Unavailable"),
            message: message,
            actionTitle: String(localized: "Try Again"),
            hints: [
                (String(localized: "Network"), String(localized: "Check Wi-Fi or cellular data")),
                (String(localized: "Backend"), String(localized: "The karaoke catalog may need a moment")),
            ],
            onAction: onRetry
        )
        .accessibilityLabel("Search unavailable")
        .accessibilityHint("Runs the last search again")
    }
}

private struct SearchNoResultsStateView: View {
    let query: String
    private let suggestions = ["Hits", "New Releases", "K-Pop", "Romance"]

    var body: some View {
        VStack(spacing: AM.Spacing.xl) {
            PulsingMusicEmptyStateMark()
            VStack(spacing: AM.Spacing.s) {
                Text("No Results")
                    .font(AM.Font.sectionHeader)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text("No songs matched \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: AM.Spacing.m) {
                Text("Explore instead")
                    .font(AM.Font.eyebrow)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                LazyVGrid(
                    columns: AM.Layout.adaptiveGridColumns(minimum: 132, spacing: AM.Spacing.s),
                    spacing: AM.Spacing.s
                ) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        NavigationLink(
                            destination: SearchCategorySongCollectionView(
                                title: suggestion,
                                query: suggestion
                            )
                        ) {
                            Text(suggestion)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.appSecondaryBackground, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(Color.appDivider, lineWidth: 0.6)
                                }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
                    }
                }
            }
            .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .accessibilityElement(children: .contain)
    }
}

private struct SearchRecoveryStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let hints: [(String, String)]
    let onAction: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var entranceAnimation: Animation? {
        reduceMotion ? nil : AppMotion.standard
    }


    var body: some View {
        VStack(spacing: AM.Spacing.xl) {
            PulsingMusicEmptyStateMark()
                .scaleEffect(hasAppeared ? 1 : 0.94)
                .opacity(hasAppeared ? 1 : 0)

            VStack(spacing: AM.Spacing.s) {
                Text(title)
                    .font(AM.Font.sectionHeader)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: 330)

            MusicEmptyActionButton(title: actionTitle) {
                AppHaptic.selection.play()
                onAction()
            }

            VStack(spacing: AM.Spacing.s) {
                ForEach(hints, id: \.0) { hint in
                    HStack(spacing: AM.Spacing.s) {
                        Circle()
                            .fill(Color.appPlaceholderSecondary)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hint.0)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(hint.1)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, AM.Spacing.m)
                    .padding(.vertical, AM.Spacing.s)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
                }
            }
            .frame(maxWidth: 340)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .onAppear {
            withOptionalAnimation(entranceAnimation) {
                hasAppeared = true
            }
        }
    }
}


private struct SearchCategoryLoadingView: View {
    let title: String
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MusicArtworkPlaceholder(cornerRadius: AM.Radius.hero)
                    .frame(width: 240, height: 240)
                    .amShadow(AM.Shadow.heroIdle)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text(title)
                        .font(AM.Font.sectionHeader)
                        .multilineTextAlignment(.center)
                    Text("Loading songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                CenteredLoadingView(minHeight: 160, label: String(localized: "Loading \(title) songs"))
            }
            .padding(.bottom, AM.Spacing.l)
        }
        .smoothScrolling()
        .accessibilityLabel("Loading \(title) songs")
    }
}

private struct SearchCategoryEmptyView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        SearchRecoveryStateView(
            title: String(localized: "No Songs"),
            message: message,
            actionTitle: String(localized: "Refresh"),
            hints: [
                (String(localized: "Category"), String(localized: "Try a broader style or mood")),
                (String(localized: "Catalog"), String(localized: "New songs appear as the library updates")),
            ],
            onAction: onRetry
        )
        .accessibilityLabel("No songs")
        .accessibilityHint("Refreshes this category")
    }
}

private struct SearchFeaturedShortcutTile: View {
    let title: String
    var subtitle: String?
    let gradient: [Color]
    var artworkURL: URL?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var optimizedArtworkURL: URL? {
        guard let artworkURL else { return nil }
        return ArtworkURLBuilder.variantURL(from: artworkURL, variant: .card) ?? artworkURL
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            LinearGradient(
                colors: [Color.black.opacity(0.02), Color.black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
            .shadow(color: .black.opacity(0.34), radius: 4, x: 0, y: 1)
            .padding(AM.Spacing.l)
            .allowsHitTesting(false)
        }
        .frame(height: isCompactWidth ? 124 : 144)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        if let artworkURL = optimizedArtworkURL {
            RemoteArtworkImage(url: artworkURL, cornerRadius: 0, contentMode: .fill)
                .allowsHitTesting(false)
            LinearGradient(
                colors: gradient.map { $0.opacity(0.76) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        } else {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
        }
    }
}

private struct CategoryTile: View {
    let title: String
    let gradient: [Color]
    var artworkURL: URL?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var optimizedArtworkURL: URL? {
        guard let artworkURL else { return nil }
        return ArtworkURLBuilder.variantURL(from: artworkURL, variant: .thumbnail) ?? artworkURL
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let artworkURL = optimizedArtworkURL {
                RemoteArtworkImage(url: artworkURL, cornerRadius: 0, contentMode: .fill)
                    .allowsHitTesting(false)
                LinearGradient(
                    colors: gradient.map { $0.opacity(0.70) },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            } else {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                .padding(AM.Spacing.m)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .allowsHitTesting(false)
        }
        .frame(height: isCompactWidth ? 92 : 102)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
    }
}

private extension String {
    var accessibilitySlug: String {
        String(unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

struct SearchResultRow: View {
    let song: Song
    var isPending: Bool = false
    let onPlay: () -> Void

    var body: some View {
        SongRow(
            song: song,
            size: .regular,
            trailing: isPending ? AnyView(ProgressView().controlSize(.small)) : nil
        )
        .songRowAccessibility(song: song, isPending: isPending, onPlay: onPlay)
    }
}
