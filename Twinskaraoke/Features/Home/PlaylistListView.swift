import Combine
import SwiftUI

struct PlaylistListView: View {
    let title: String
    let playlists: [Playlist]
    var apiURL: ((Int, Int) -> String)?
    let cols = AM.Layout.playlistGridColumns
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @StateObject private var loader = PlaylistListLoader()
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

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
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
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                            PlaylistGridCell(playlist: playlist)
                        }
                        .id(playlist.id)
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Playlists"
        )
        .animation(
            reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
            value: displayedPlaylists.map(\.id)
        )
        .onAppear {
            if let apiURL {
                loader.bootstrap(initial: playlists, urlBuilder: apiURL)
            }
            prefetchArtwork()
        }
        .onChange(of: displayedPlaylists.map(\.id)) { _, _ in
            prefetchArtwork()
        }
    }

    private func prefetchArtwork() {
        ArtworkPrefetcher.shared.prefetchPlaylists(
            Array(displayedPlaylists.prefix(12)),
            limit: 12,
            reason: "playlist list"
        )
    }
}

final class PlaylistListLoader: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var isLoadingMore = false
    private var canLoadMore = true
    private let pageSize = 25
    private var urlBuilder: ((Int, Int) -> String)?

    func bootstrap(initial: [Playlist], urlBuilder: @escaping (Int, Int) -> String) {
        guard self.urlBuilder == nil else { return }
        self.urlBuilder = urlBuilder
        playlists = initial
        canLoadMore = true
    }

    func loadMoreIfNeeded(current: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == current.id }) else { return }
        if idx >= playlists.count - 4, !isLoadingMore, canLoadMore {
            loadMore()
        }
    }

    private func loadMore() {
        guard let urlBuilder else { return }
        isLoadingMore = true
        let startIndex = playlists.count
        let urlString = urlBuilder(startIndex, pageSize)
        guard let url = URL(string: urlString) else {
            isLoadingMore = false
            return
        }
        var request = URLRequest(url: url)
        if let token = UserDefaults.standard.string(forKey: "nk.token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let items = Self.decode(data: data)
                if !items.isEmpty {
                    let existing = Set(self.playlists.map(\.id))
                    self.playlists += items.filter { !existing.contains($0.id) }
                    ArtworkPrefetcher.shared.prefetchPlaylists(
                        Array(items.prefix(12)),
                        limit: 12,
                        reason: "playlist list page"
                    )
                    self.canLoadMore = items.count >= self.pageSize
                } else {
                    self.canLoadMore = false
                }
                self.isLoadingMore = false
            }
        }.resume()
    }

    private static func decode(data: Data?) -> [Playlist] {
        guard let data else { return [] }
        let decoder = JSONDecoder()
        if let items = (try? decoder.decode(LossyArray<PlaylistListItem>.self, from: data))?.elements {
            return items.map { $0.asPlaylist() }
        }
        if let items = try? decoder.decode([PlaylistListItem].self, from: data) {
            return items.map { $0.asPlaylist() }
        }
        return []
    }
}
