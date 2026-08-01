import SwiftUI

struct NewView: View {
    @StateObject var viewModel = HomeViewModel()
    @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion

    private var loadingAnimation: Animation? {
        reduceMotion ? nil : AppMotion.spring(response: 0.38, dampingFraction: 0.84)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    Group {
                        if viewModel.isLoading, !viewModel.hasNewVisibleContent {
                            NewSkeletonView()
                                .transition(.opacity)
                        } else if !viewModel.hasNewVisibleContent,
                                  let message = viewModel.newLoadErrorMessage {
                            NewLoadFailureView(message: message) {
                                viewModel.fetchHomeData(force: true)
                            }
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
                .tabBarScrollInset()
                .musicScreenBackground()
            }
            .navigationTitle("New")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton()
                }
            }
            .refreshable { await viewModel.refresh() }
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
                NewSongRail(title: "Trending Songs", songs: viewModel.trending)
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
                        NewSongRail(title: "Trending Songs", songs: viewModel.trending)
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

    private func prefetchVisibleArtwork() {
        let songs =
            [viewModel.newReleases.first, viewModel.trending.first].compactMap { $0 }
            + Array(viewModel.newReleases.prefix(12))
            + Array(viewModel.trending.prefix(8))
        ArtworkPrefetcher.shared.prefetchSongs(songs, limit: 18, reason: "new songs")
        ArtworkPrefetcher.shared.prefetchPlaylists(
            Array((viewModel.recentPlaylists + recentlyPlayed.playlists).prefix(8)),
            limit: 12,
            reason: "new playlists"
        )
    }
}

private struct NewLoadFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: AM.Spacing.l) {
            MusicEmptyState(title: "Unable to Load New Music", message: message)
            MusicEmptyActionButton(title: "Try Again", action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AM.Spacing.xxl)
    }
}
