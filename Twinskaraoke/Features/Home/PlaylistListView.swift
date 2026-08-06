import SwiftUI

struct PlaylistListView: View {
    @Namespace private var zoomNamespace
    let title: String
    let playlists: [Playlist]
    var apiURL: ((Int, Int) -> String)?
    let cols = AM.Layout.playlistGridColumns
    @State private var loader = PlaylistListLoader()
    @State private var searchText = ""
    private var allPlaylists: [Playlist] {
        loader.playlists.isEmpty ? playlists : loader.playlists
    }

    private var displayedPlaylists: [Playlist] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allPlaylists }
        return allPlaylists.filter { playlist in
            playlist.name.localizedCaseInsensitiveContains(query)
        }
    }


    var body: some View {
        ScrollView {
            if displayedPlaylists.isEmpty {
                MusicEmptyState(
                    title: searchText.isEmpty ? "No Playlists" : "No Results",
                    message: searchText.isEmpty
                        ? "Playlists will appear here."
                        : "Try another playlist name."
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: cols, spacing: AM.Spacing.l) {
                    ForEach(displayedPlaylists) { playlist in
                        ZoomNavigationLink(id: playlist.id, in: zoomNamespace) {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            PlaylistGridCell(playlist: playlist)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("PlaylistList.\(playlist.id)")
                        .contextMenu {
                            PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
                        } preview: {
                            PlaylistContextPreview(playlist: playlist)
                        }
                        .onAppear {
                            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                loader.loadMoreIfNeeded(current: playlist)
                            }
                        }
                    }
                }
                .padding(.horizontal, AM.Spacing.screenMargin)
                .padding(.vertical, AM.Spacing.m)
            }
            if loader.isLoadingMore {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 44)
                    .padding(.vertical, AM.Spacing.m)
            }
        }
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: "Search Playlists"
        )
        .secondarySearchBehavior()
        .onAppear {
            if let apiURL {
                loader.bootstrap(initial: playlists, urlBuilder: apiURL)
            }
            prefetchArtwork()
        }
        // Page 1 may land after onAppear; bootstrap re-runs only while the
        // loader is still empty (see PlaylistListLoader.bootstrap).
        .onChange(of: playlists.map(\.id)) { _, _ in
            if let apiURL {
                loader.bootstrap(initial: playlists, urlBuilder: apiURL)
            }
        }
        .onChange(of: Array(displayedPlaylists.prefix(12)).map(\.id)) { _, _ in
            prefetchArtwork()
        }
        .onDisappear {
            ArtworkPrefetcher.shared.cancel(reason: "playlist list")
        }
    }

    private func prefetchArtwork() {
        ArtworkPrefetcher.shared.prefetchPlaylists(
            Array(displayedPlaylists.prefix(12)),
            limit: 12,
            reason: "playlist list",
            variant: .thumbnail
        )
    }
}
