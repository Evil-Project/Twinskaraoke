import SwiftUI

struct SearchView: View {
    @StateObject var viewModel = SearchViewModel()

    @ObservedObject private var playback = PlaybackRowState.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var pendingSongID: String?
    @State private var playbackTask: Task<Void, Never>?

    private var stateChangeAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)
    }

    private var subtleStateTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private var resultsEmptyTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
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
                Group {
                    if viewModel.isSearching, viewModel.results.isEmpty {
                        SearchResultsLoadingView()
                            .transition(.opacity)
                    } else if let errorMessage = viewModel.searchErrorMessage,
                              viewModel.results.isEmpty,
                              !viewModel.searchText.isEmpty
                    {
                        SearchErrorStateView(message: errorMessage) {
                            viewModel.retrySearch()
                        }
                        .transition(subtleStateTransition)
                    } else if viewModel.results.isEmpty, !viewModel.searchText.isEmpty {
                        SearchNoResultsStateView(query: viewModel.searchText)
                            .transition(resultsEmptyTransition)
                    } else if viewModel.results.isEmpty {
                        BrowseCategoriesView(availableWidth: proxy.size.width)
                            .transition(.opacity)
                    } else {
                        List {
                            SearchResultsSummaryHeader(
                                query: viewModel.searchText,
                                resultCount: viewModel.results.count
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)

                            ForEach(viewModel.results) { song in
                                Button {
                                    playSelection(song)
                                } label: {
                                    SearchResultRow(song: song, isPending: pendingSongID == song.id) {
                                        playSelection(song)
                                    }
                                }
                                .disabled(pendingSongID != nil)
                                .buttonStyle(PressableButtonStyle())
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                .musicScreenBackground()
                .animation(
                    stateChangeAnimation,
                    value: "\(viewModel.isSearching)-\(viewModel.results.count)-\(viewModel.searchText.isEmpty)"
                )
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
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Songs, Artists, Lyrics, and More"
            )
            .onChange(of: playback.currentSongID) { _, currentSongID in
                guard currentSongID == pendingSongID else { return }
                pendingSongID = nil
            }
            .onChange(of: viewModel.results.map(\.id)) { _, _ in
                ArtworkPrefetcher.shared.prefetchSongs(
                    Array(viewModel.results.prefix(18)),
                    limit: 18,
                    reason: "search results"
                )
            }
            .onDisappear {
                playbackTask?.cancel()
                playbackTask = nil
                pendingSongID = nil
            }
        }
    }

    private func playSelection(_ song: Song) {
        guard pendingSongID == nil else { return }
        guard playback.currentSongID != song.id else { return }
        AppHaptic.selection.play()
        pendingSongID = song.id
        let context = viewModel.results
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            AudioPlayerManager.shared.play(song: song, context: context)
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, pendingSongID == song.id else { return }
            pendingSongID = nil
        }
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
                    .font(.title2.bold())
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 12)
                Text(resultCountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }
            if !trimmedQuery.isEmpty {
                Text("Results for \"\(trimmedQuery)\"")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var resultCountText: String {
        resultCount == 1 ? "1 song" : "\(resultCount) songs"
    }
}

private struct BrowseCategoriesView: View {
    let availableWidth: CGFloat
    @StateObject private var genresVM = GenresViewModel()
    @StateObject private var topChartVM = TopChartViewModel()
    @StateObject private var publicPlaylistsVM = PublicPlaylistsViewModel()
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
        .bottomChromeScrollTracking()
        .musicScreenBackground()
        .scrollIndicators(.hidden)
        .tabBarScrollInset()
        .refreshable {
            AppHaptic.selection.play()
            genresVM.loadIfNeeded()
            topChartVM.loadIfNeeded()
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
            VStack(alignment: .leading, spacing: AM.Spacing.l) {
                Text("Featured")
                    .font(AM.Font.sectionHeader)
                    .foregroundStyle(.primary)
                featuredGrid(horizontalPadding: 0)
            }
            .frame(width: 390, alignment: .topLeading)

            VStack(alignment: .leading, spacing: AM.Spacing.l) {
                Text("Genres")
                    .font(AM.Font.sectionHeader)
                    .foregroundStyle(.primary)
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
            AMSectionHeader("Featured")
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
                        Color(red: 0.98, green: 0.12, blue: 0.22),
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
                    title: "Public Playlists",
                    subtitle: publicPlaylistsVM.playlists.isEmpty
                        ? "Community mixes"
                        : "\(publicPlaylistsVM.playlists.count) playlists",
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
            .accessibilityHint("Opens public karaoke playlists")
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var genresSection: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.m) {
            AMSectionHeader("Genres")
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
            CenteredLoadingView(label: "Loading categories")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if genresVM.genres.isEmpty {
            MusicEmptyState(
                title: "Genres Unavailable",
                message: "Pull down to refresh browse categories."
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
                    .onAppear { genresVM.loadMoreIfNeeded(current: genre) }
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
        let stable = genres[abs(name.hashValue) % genres.count]
        return stable.1
    }
}

private struct TopChartCollectionView: View {
    @ObservedObject var viewModel: TopChartViewModel

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
    @ObservedObject var viewModel: PublicPlaylistsViewModel

    var body: some View {
        PlaylistListView(
            title: "Public Playlists",
            playlists: viewModel.playlists,
            apiURL: { startIndex, pageSize in
                viewModel.urlForList(startIndex: startIndex, pageSize: pageSize)
            }
        )
        .task {
            viewModel.loadIfNeeded()
        }
    }
}

struct GenreDetailView: View {
    let genre: GenreSummary
    @ObservedObject var viewModel: GenresViewModel
    let palette: [Color]
    @State private var isLoadingDetail = false

    var body: some View {
        let songs = viewModel.allSongs[genre.id] ?? []
        Group {
            if isLoadingDetail, songs.isEmpty {
                GenreDetailLoadingView(genre: genre)
                    .transition(.opacity)
            } else {
                BrowseSongCollectionView(
                    title: genre.name,
                    songs: songs
                )
                .transition(.opacity)
            }
        }
        .task {
            await loadGenreDetail()
        }
    }

    private func loadGenreDetail() async {
        guard viewModel.allSongs[genre.id] == nil else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }

        guard let url = URL(string: "\(StorageHost.api)/api/genres/\(genre.id)") else {
            return
        }

        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let detail = try? JSONDecoder().decode(GenreDetail.self, from: data),
               let songs = detail.songs
            {
                await MainActor.run {
                    viewModel.allSongs[genre.id] = songs
                    if let first = songs.first {
                        viewModel.firstSongs[genre.id] = first
                    }
                    let artURL = songs.first(where: { $0.hasOwnArtwork })?.imageURL
                    if let artURL {
                        viewModel.artworkURLs[genre.id] = artURL
                    }
                }
            }
        } catch {}
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
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Loading songs")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                CenteredLoadingView(minHeight: 160, label: "Loading \(genre.name) songs")
            }
            .padding(.bottom, AM.Spacing.l)
        }
        .smoothScrolling()
        .bottomChromeScrollTracking()
        .tabBarScrollInset()
        .accessibilityLabel("Loading \(genre.name) songs")
    }
}

struct SearchCategorySongCollectionView: View {
    let title: String
    let query: String
    @StateObject private var loader: SearchCategorySongsViewModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

    private var categoryStateAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    init(title: String, query: String) {
        self.title = title
        self.query = query
        _loader = StateObject(wrappedValue: SearchCategorySongsViewModel(query: query))
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
            loader.refresh()
        }
        .task {
            loader.loadIfNeeded()
        }
        .animation(categoryStateAnimation, value: loader.isLoading)
        .animation(categoryStateAnimation, value: loader.songs.count)
    }
}

private struct SearchResultsLoadingView: View {
    var body: some View {
        CenteredLoadingView(label: "Searching songs")
    }
}

private struct SearchErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        SearchRecoveryStateView(
            title: "Search Unavailable",
            message: message,
            actionTitle: "Try Again",
            hints: [
                ("Network", "Check Wi-Fi or cellular data"),
                ("Backend", "The karaoke catalog may need a moment"),
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
            SearchStateGlyph()
            VStack(spacing: AM.Spacing.s) {
                Text("No Results")
                    .font(.title2.bold())
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                Text("No songs matched \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: AM.Spacing.m) {
                Text("Explore instead")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
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
                                .foregroundStyle(Color.primary)
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var hasAppeared = false

    private var entranceAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        VStack(spacing: AM.Spacing.xl) {
            SearchStateGlyph()
                .scaleEffect(hasAppeared ? 1 : 0.94)
                .opacity(hasAppeared ? 1 : 0)

            VStack(spacing: AM.Spacing.s) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
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
                                .foregroundStyle(Color.primary)
                            Text(hint.1)
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
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

private struct SearchStateGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var isPulsing = false

    var body: some View {
        MusicEmptyStateMark()
            .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.03 : 0.98))
            .onAppear {
                guard !reduceMotion else {
                    isPulsing = false
                    return
                }
                withOptionalAnimation(pulseAnimation) {
                    isPulsing = true
                }
            }
            .onChange(of: reduceMotion) { _, reduceMotion in
                if reduceMotion {
                    withOptionalAnimation(nil) {
                        isPulsing = false
                    }
                } else {
                    withOptionalAnimation(pulseAnimation) {
                        isPulsing = true
                    }
                }
            }
            .accessibilityHidden(true)
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var pulseAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.78)
            .repeatForever(autoreverses: true)
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
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Loading songs")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                CenteredLoadingView(minHeight: 160, label: "Loading \(title) songs")
            }
            .padding(.bottom, AM.Spacing.l)
        }
        .smoothScrolling()
        .bottomChromeScrollTracking()
        .tabBarScrollInset()
        .accessibilityLabel("Loading \(title) songs")
    }
}

private struct SearchCategoryEmptyView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        SearchRecoveryStateView(
            title: "No Songs",
            message: message,
            actionTitle: "Refresh",
            hints: [
                ("Category", "Try a broader style or mood"),
                ("Catalog", "New songs appear as the library updates"),
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
        .amShadow(AM.Shadow.card)
        .contentShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        if let artworkURL {
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let artworkURL {
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
        .amShadow(AM.Shadow.card)
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
