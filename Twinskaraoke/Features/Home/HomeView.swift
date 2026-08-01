import SwiftUI

struct HomeView: View {
    @Environment(HomeViewModel.self) var viewModel
    private let recentlyPlayed = RecentlyPlayedStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var artworkPrefetchTracker = ArtworkPrefetchTracker()

    private var loadingAnimation: Animation? {
        reduceMotion ? nil : AppMotion.standard
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
            .refreshable { await viewModel.refreshHomeData() }
            .task { viewModel.fetchHomeData() }
            .onChange(of: artworkPrefetchSignature) { _, _ in
                prefetchVisibleArtworkIfNeeded()
            }
            .onAppear {
                prefetchVisibleArtworkIfNeeded()
            }
            .onDisappear {
                artworkPrefetchTracker.reset()
                ArtworkPrefetcher.shared.cancel(reason: "home songs")
                ArtworkPrefetcher.shared.cancel(reason: "home playlists")
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
                .shelfEntrance(index: 0)
                

            if !recentlyPlayed.playlists.isEmpty {
                PlaylistCarousel(title: "Recently Played", playlists: recentlyPlayed.playlists)
                    .shelfEntrance(index: 1)
            }

            if !viewModel.suggestions.isEmpty {
                HomeSongSection(title: "Made for You", songs: viewModel.suggestions)
                    .shelfEntrance(index: 2)
            }

            latestSingleSection()
                .shelfEntrance(index: 3)
            
            if !viewModel.newReleases.isEmpty {
                HomeSongSection(title: "New Releases", songs: viewModel.newReleases)
                    .shelfEntrance(index: 4)
            }

            if !viewModel.trending.isEmpty {
                HomeSongSection(title: "More to Explore", songs: viewModel.trending)
                    .shelfEntrance(index: 5)
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
            .shelfEntrance(index: 0)

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
                .shelfEntrance(index: 1)

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
                .shelfEntrance(index: 2)
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

    private var artworkPrefetchSongs: [Song] {
        [homeHeroSong, homeSecondarySong].compactMap { $0 }
            + Array(viewModel.suggestions.prefix(8))
            + Array(viewModel.newReleases.prefix(8))
            + Array(viewModel.trending.prefix(8))
    }

    private var artworkPrefetchPlaylists: [Playlist] {
        Array((recentlyPlayed.playlists + viewModel.recentPlaylists).prefix(8))
    }

    private var artworkPrefetchSignature: ArtworkPrefetchSignature {
        ArtworkPrefetchSignature(
            songs: artworkPrefetchSongs,
            playlists: artworkPrefetchPlaylists
        )
    }

    private func prefetchVisibleArtworkIfNeeded() {
        artworkPrefetchTracker.prefetch(
            signature: artworkPrefetchSignature,
            songs: artworkPrefetchSongs,
            playlists: artworkPrefetchPlaylists,
            songReason: "home songs",
            playlistReason: "home playlists",
            songLimit: 18,
            playlistLimit: 12
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

/// Fades and rises a Home shelf into place once, staggered by its position,
/// when the loaded content first replaces the skeleton.
private struct ShelfEntranceModifier: ViewModifier {
    let index: Int
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .onAppear {
                guard !appeared else { return }
                guard !reduceMotion else {
                    appeared = true
                    return
                }
                withAnimation(
                    AppMotion.standard
                        .delay(Double(index) * 0.05)
                ) {
                    appeared = true
                }
            }
    }
}

private extension View {
    func shelfEntrance(index: Int) -> some View {
        modifier(ShelfEntranceModifier(index: index))
    }
}
