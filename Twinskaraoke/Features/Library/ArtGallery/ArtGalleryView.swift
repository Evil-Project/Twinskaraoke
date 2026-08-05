import SwiftUI

struct ArtGalleryView: View {
    @Namespace private var zoomNamespace
    @State private var viewModel = ArtGalleryViewModel()
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            if viewModel.isLoading, viewModel.artists.isEmpty {
                ArtGallerySkeletonView()
                    .padding(.top, 16)
                    .transition(.opacity)
            } else if viewModel.artists.isEmpty {
                ArtGalleryEmptyState(isError: viewModel.loadFailed) {
                    viewModel.fetch(force: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 96)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    if let featured = featuredArt {
                        ZoomNavigationLink(id: featured.art.id, in: zoomNamespace) {
                            ArtDetailView(art: featured.art, artist: featured.artist)
                        } label: {
                            FeaturedArtCard(art: featured.art, artist: featured.artist)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded { AppHaptic.selection.play() })
                        .contextMenu {
                            if let url = featured.art.fullHDImageURL ?? featured.art.imageURL {
                                ShareLink(item: url) {
                                    Label("Share Artwork", systemImage: "square.and.arrow.up")
                                }
                            }
                            if let upvotes = featured.art.upvotes, upvotes > 0 {
                                Label("\(upvotes) likes", systemImage: "heart.fill")
                            }
                        } preview: {
                            GalleryArtPreview(art: featured.art, artist: featured.artist)
                        }
                        .padding(.horizontal, 16)
                    }
                    GalleryStatsStrip(
                        artistCount: viewModel.artists.count,
                        artworkCount: artworkCount,
                        totalUpvotes: totalUpvotes
                    )
                    .padding(.horizontal, 16)
                    if !topArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            GallerySectionHeader(title: "Featured Artists")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(topArtists) { artist in
                                        ZoomNavigationLink(id: artist.id, in: zoomNamespace) {
                                            ArtistArtsView(artist: artist)
                                        } label: {
                                            ArtistCircleCard(artist: artist)
                                        }
                                        .buttonStyle(PressableButtonStyle())
                                        .simultaneousGesture(TapGesture().onEnded { AppHaptic.selection.play() })
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        GallerySectionHeader(title: "All Artists")
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.artists.enumerated()), id: \.element.id) { idx, artist in
                                NavigationLink {
                                    ArtistArtsView(artist: artist)
                                } label: {
                                    ArtistListRow(artist: artist)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { AppHaptic.selection.play() })
                                if idx < viewModel.artists.count - 1 {
                                    Divider().padding(.leading, 78)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle("Art Gallery")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            AppHaptic.selection.play()
            await viewModel.refreshGallery()
        }
        .onAppear { viewModel.fetch() }
    }

    private var featuredArt: (art: GalleryArt, artist: GalleryArtist)? {
        viewModel.artists
            .flatMap { artist in
                (artist.arts ?? []).map { (art: $0, artist: artist) }
            }
            .max { ($0.art.upvotes ?? 0) < ($1.art.upvotes ?? 0) }
    }

    private var topArtists: [GalleryArtist] {
        Array(viewModel.artists.prefix(12))
    }

    private var artworkCount: Int {
        viewModel.artists.reduce(0) { $0 + ($1.arts?.count ?? 0) }
    }

    private var totalUpvotes: Int {
        viewModel.artists.reduce(0) { partial, artist in
            partial + (artist.arts ?? []).reduce(0) { $0 + ($1.upvotes ?? 0) }
        }
    }
}
