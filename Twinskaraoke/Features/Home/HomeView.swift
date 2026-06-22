import SwiftUI

struct HomeView: View {
    @StateObject var viewModel = HomeViewModel()
    @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

    private var loadingAnimation: Animation? {
        reduceMotion ? nil : AppMotion.spring(response: 0.38, dampingFraction: 0.84)
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    Group {
                        if viewModel.isLoading {
                            HomeSkeletonView()
                                .transition(.opacity)
                        } else {
                            homeOverview(availableWidth: proxy.size.width)
                                .transition(.opacity)
                        }
                    }
                    .animation(loadingAnimation, value: viewModel.isLoading)
                    .padding(.top, AM.Spacing.l)
                    .padding(.bottom, AM.Spacing.l)
                }
                .smoothScrolling()
                .tabBarScrollInset()
                .musicScreenBackground()
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton()
                }
            }
            .refreshable { viewModel.fetchHomeData(force: true) }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                guard !isLoading else { return }
                prefetchVisibleArtwork()
            }
            .onAppear {
                prefetchVisibleArtwork()
            }
        }
    }

    @ViewBuilder
    private func homeOverview(availableWidth: CGFloat) -> some View {
        if AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        ) {
            wideHomeOverview
        } else {
            compactHomeOverview
        }
    }

    private var compactHomeOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            topPicksShelf()

            if !recentlyPlayed.playlists.isEmpty {
                PlaylistCarousel(title: "Recently Played", playlists: recentlyPlayed.playlists)
            }

            if !viewModel.suggestions.isEmpty {
                HomeSongSection(title: "Made for You", songs: viewModel.suggestions)
            }

            latestSingleSection()

            if !viewModel.newReleases.isEmpty {
                HomeSongSection(title: "New Releases", songs: viewModel.newReleases)
            }

            if !viewModel.trending.isEmpty {
                HomeSongSection(title: "More to Explore", songs: viewModel.trending)
            }
        }
    }

    private var wideHomeOverview: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
            WideHomeHero(
                song: homeHeroSong,
                context: homeHeroContext,
                playlist: viewModel.recentPlaylists.first,
                secondarySong: homeSecondarySong,
                secondaryContext: viewModel.suggestions.isEmpty ? viewModel.trending : viewModel.suggestions
            )

            HStack(alignment: .top, spacing: AM.Spacing.xxl) {
                VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
                    topPicksShelf(horizontalPadding: 0)

                    if !recentlyPlayed.playlists.isEmpty {
                        PlaylistCarousel(
                            title: "Recently Played",
                            playlists: recentlyPlayed.playlists,
                            horizontalPadding: 0
                        )
                    }

                    if !viewModel.suggestions.isEmpty {
                        HomeSongSection(title: "Made for You", songs: viewModel.suggestions, horizontalPadding: 0)
                    }
                }
                .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
                    latestSingleSection(horizontalPadding: 0)

                    if !viewModel.newReleases.isEmpty {
                        WideSongListPanel(title: "New Releases", songs: Array(viewModel.newReleases.prefix(6)))
                    }

                    if !viewModel.trending.isEmpty {
                        WideSongListPanel(title: "More to Explore", songs: Array(viewModel.trending.prefix(6)))
                    }
                }
                .frame(
                    width: AM.Layout.wideInspectorWidth,
                    alignment: .topLeading
                )
            }
        }
        .frame(maxWidth: AM.Layout.wideContentMaxWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Home.WideOverview")
    }

    private var homeHeroSong: Song? {
        viewModel.latestSingle ?? viewModel.suggestions.first ?? viewModel.newReleases.first ?? viewModel.trending.first
    }

    private var homeSecondarySong: Song? {
        viewModel.suggestions.dropFirst().first ?? viewModel.newReleases.dropFirst().first ?? viewModel.trending.first
    }

    private var homeHeroContext: [Song] {
        if !viewModel.latestSingleContext.isEmpty { return viewModel.latestSingleContext }
        if !viewModel.suggestions.isEmpty { return viewModel.suggestions }
        if !viewModel.newReleases.isEmpty { return viewModel.newReleases }
        return viewModel.trending
    }

    private func prefetchVisibleArtwork() {
        let songs =
            [homeHeroSong, homeSecondarySong].compactMap { $0 }
            + Array(viewModel.suggestions.prefix(8))
            + Array(viewModel.newReleases.prefix(8))
            + Array(viewModel.trending.prefix(8))
        ArtworkPrefetcher.shared.prefetchSongs(songs, limit: 18, reason: "home songs")
        ArtworkPrefetcher.shared.prefetchPlaylists(
            Array((recentlyPlayed.playlists + viewModel.recentPlaylists).prefix(8)),
            limit: 12,
            reason: "home playlists"
        )
    }

    @ViewBuilder
    private func topPicksShelf(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
        if !viewModel.recentPlaylists.isEmpty {
            PlaylistCarousel(
                title: "Top Picks for You",
                playlists: viewModel.recentPlaylists,
                isLoadingMore: viewModel.isLoadingMoreTopPicks,
                onAppearItem: { viewModel.loadMoreTopPicksIfNeeded(current: $0) },
                apiURL: { startIndex, pageSize in
                    viewModel.topPicksURLForList(startIndex: startIndex, pageSize: pageSize)
                },
                horizontalPadding: horizontalPadding
            )
        }
    }

    @ViewBuilder
    private func latestSingleSection(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
        if let latestSingle = viewModel.latestSingle {
            LatestSingleSection(
                song: latestSingle,
                context: viewModel.latestSingleContext.isEmpty ? [latestSingle] : viewModel.latestSingleContext,
                horizontalPadding: horizontalPadding
            )
        }
    }
}
