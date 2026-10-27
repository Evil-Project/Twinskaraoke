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

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedPlaylists: [Playlist] {
        let query = trimmedQuery
        guard !query.isEmpty else { return allPlaylists }
        return loader.matches(for: query, in: allPlaylists)
    }


    var body: some View {
        ScrollView {
            if displayedPlaylists.isEmpty, !trimmedQuery.isEmpty, loader.isSearching {
                // Not "No Results" yet: the server has not answered.
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else if displayedPlaylists.isEmpty {
                MusicEmptyState(
                    title: searchText.isEmpty ? String(localized: "No Playlists") : String(localized: "No Results"),
                    message: searchText.isEmpty
                        ? String(localized: "Playlists will appear here.")
                        : String(localized: "Try another playlist name.")
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
        .task(id: trimmedQuery) {
            await loader.search(trimmedQuery)
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
