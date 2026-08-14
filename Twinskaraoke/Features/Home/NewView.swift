import SwiftUI

struct NewView: View {
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
                            NewSkeletonView()
                                .transition(.opacity)
                        } else {
                            newOverview(availableWidth: proxy.size.width)
                                .transition(.opacity)
                        }
                    }
                    .animation(loadingAnimation, value: viewModel.isLoading)
                    .padding(.top, AM.Spacing.m)
                    .padding(.bottom, AM.Spacing.l)
                }
                .smoothScrolling()
                .musicScreenBackground()
            }
            .navigationTitle("New")
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
                ArtworkPrefetcher.shared.cancel(reason: "new songs")
                ArtworkPrefetcher.shared.cancel(reason: "new playlists")
            }
        }
    }

    @ViewBuilder
    private func newOverview(availableWidth: CGFloat) -> some View {
        if AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        ) {
            wideNewOverview
        } else {
            compactNewOverview
        }
    }

    private var compactNewOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !viewModel.newReleases.isEmpty {
                NewFeaturedRail(
                    primary: viewModel.newReleases.first,
                    secondary: viewModel.trending.first,
                    songs: viewModel.newReleases
                )
            }

            if !viewModel.newReleases.isEmpty {
                NewSongRail(title: "Up Next", songs: Array(viewModel.newReleases.prefix(8)))
            }

            if !viewModel.trending.isEmpty {
                NewSongListPreview(title: "Best New Songs", songs: Array(viewModel.trending.prefix(5)))
            }

            if !viewModel.recentPlaylists.isEmpty {
                NewPlaylistRail(title: "New This Week", playlists: viewModel.recentPlaylists)
            }

            if !viewModel.newReleases.isEmpty {
                NewSongRail(title: "New Releases", songs: viewModel.newReleases)
            }

            if !recentlyPlayed.playlists.isEmpty {
                NewPlaylistRail(title: "Recently Released", playlists: recentlyPlayed.playlists)
            }

            if !viewModel.trending.isEmpty {
                NewSongRail(title: "More to Explore", songs: viewModel.trending)
            }
        }
    }

    private var wideNewOverview: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
            WideNewHero(
                primary: viewModel.newReleases.first,
                secondary: viewModel.trending.first,
                context: viewModel.newReleases.isEmpty ? viewModel.trending : viewModel.newReleases,
                playlist: viewModel.recentPlaylists.first
            )

            if !viewModel.newReleases.isEmpty {
                NewFeaturedRail(
                    primary: viewModel.newReleases.first,
                    secondary: viewModel.trending.first,
                    songs: viewModel.newReleases
                )
            }

            HStack(alignment: .top, spacing: AM.Spacing.xxl) {
                VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
                    if !viewModel.newReleases.isEmpty {
                        NewSongRail(title: "Up Next", songs: Array(viewModel.newReleases.prefix(8)))
                    }

                    if !viewModel.recentPlaylists.isEmpty {
                        NewPlaylistRail(title: "New This Week", playlists: viewModel.recentPlaylists)
                    }

                    if !viewModel.newReleases.isEmpty {
                        NewSongRail(title: "New Releases", songs: viewModel.newReleases)
                    }

                    if !recentlyPlayed.playlists.isEmpty {
                        NewPlaylistRail(title: "Recently Released", playlists: recentlyPlayed.playlists)
                    }

                    if !viewModel.trending.isEmpty {
                        NewSongRail(title: "More to Explore", songs: viewModel.trending)
                    }
                }
                .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
                    if !viewModel.trending.isEmpty {
                        NewSongListPreview(
                            title: "Best New Songs",
                            songs: Array(viewModel.trending.prefix(5)),
                            horizontalPadding: 0
                        )
                    }
                }
                .frame(width: AM.Layout.wideInspectorWidth, alignment: .topLeading)
            }
        }
        .frame(maxWidth: AM.Layout.wideContentMaxWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("New.WideOverview")
    }

    private var artworkPrefetchSongs: [Song] {
        [viewModel.newReleases.first, viewModel.trending.first].compactMap { $0 }
            + Array(viewModel.newReleases.prefix(12))
            + Array(viewModel.trending.prefix(8))
    }

    private var artworkPrefetchPlaylists: [Playlist] {
        Array((viewModel.recentPlaylists + recentlyPlayed.playlists).prefix(8))
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
            songReason: "new songs",
            playlistReason: "new playlists",
            songLimit: 18,
            playlistLimit: 12
        )
    }
}
