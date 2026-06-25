import SwiftUI

struct ArtGalleryView: View {
    @StateObject private var viewModel = ArtGalleryViewModel()
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
                        NavigationLink {
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
                                        NavigationLink {
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
        .navigationTitle("Art Gallery")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            AppHaptic.selection.play()
            viewModel.fetch(force: true)
        }
        .onAppear { viewModel.fetch() }
        .animation(
            reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84),
            value: viewModel.artists.count
        )
    }

    private var featuredArt: (art: GalleryArt, artist: GalleryArtist)? {
        for artist in viewModel.artists {
            if let art = artist.arts?.max(by: { ($0.upvotes ?? 0) < ($1.upvotes ?? 0) }) {
                return (art, artist)
            }
        }
        return nil
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
