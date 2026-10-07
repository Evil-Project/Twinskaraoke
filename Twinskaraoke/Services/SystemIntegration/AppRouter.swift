import SwiftUI
import Observation

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var section: RootSection = .home
    var detail: AppRoute?
    var lyricsRequest = 0
    var requestID = UUID()
    var hasPendingRoute = false
    private var splashRoutes: [AppRoute] = []
    private let isSplashBlocking: () -> Bool
    /// Injects the splash blocking predicate used to defer incoming routes.
    init(isSplashBlocking: @escaping () -> Bool = { SplashCoordinator.shared.isBlocking }) {
        self.isSplashBlocking = isSplashBlocking
    }
    /// Drains queued routes in order when the walkthrough gate and detail sheet allow it.
    func resumeAfterSplash() {
        guard !isSplashBlocking() else { return }
        while !splashRoutes.isEmpty && detail == nil {
            apply(splashRoutes.removeFirst())
        }
    }
    /// Clears the current detail so the dismissal observer can resume queued routes.
    func dismissDetail() {
        detail = nil
    }
    /// Queues navigation during the splash gate or an existing route backlog.
    func open(_ route: AppRoute) {
        if isSplashBlocking() || !splashRoutes.isEmpty {
            splashRoutes.append(route)
            resumeAfterSplash()
            return
        }
        apply(route)
    }
    /// Presents the requested app route after navigation blockers have cleared.
    private func apply(_ route: AppRoute) {
        hasPendingRoute = true
        detail = nil
        switch route {
        case .home: section = .home
        case .radio: section = .radio
        case .search: section = .search
        case .library: section = .library
        case .nowPlaying: NowPlayingPresentation.shared.expand()
        case .lyrics:
            lyricsRequest += 1
            NowPlayingPresentation.shared.expand()
        case .song, .playlist:
            section = .library
            detail = route
        }
        requestID = UUID()
    }
}

struct RoutedDetailView: View {
    let route: AppRoute
    @State private var playlist: Playlist?
    @State private var song: Song?
    @State private var failed = false
    var body: some View {
        Group {
            if route == .playlist("__downloads__") { DownloadedSongsView() }
            else if let playlist { PlaylistDetailView(playlist: playlist) }
            else if let song {
                VStack(spacing: 20) {
                    Text(song.title).font(.title).multilineTextAlignment(.center)
                    Text(song.displayArtist).foregroundStyle(.secondary)
                    Button("Play", systemImage: "play.fill") {
                        AudioPlayerManager.shared.playInOrder(song: song, context: [song])
                        NowPlayingPresentation.shared.expand()
                    }.buttonStyle(.borderedProminent)
                }.padding()
            } else if failed {
                ContentUnavailableView("Unable to Open", systemImage: "wifi.exclamationmark", description: Text("Check your connection and account, then try again."))
            } else { ProgressView() }
        }
        .task(id: String(describing: route)) {
            do {
                switch route {
                case .playlist(let id):
                    if id == "__downloads__" { return }
                    if id == Playlist.favoritesID {
                        guard CredentialStore.isAuthenticated else { throw SystemIntentError.signIn }
                        playlist = Playlist(id: id, name: String(localized: "Favorites"), songCount: FavoritesManager.shared.favoriteIDs.count, mosaicMedia: nil, songListDTOs: nil, isPersonal: true)
                    } else {
                        let known = RecentlyPlayedStore.shared.playlists + SavedPlaylistsStore.shared.playlists + PinnedPlaylistsStore.shared.playlists + UserPlaylistsManager.shared.playlists.map { $0.asPlaylist() }
                        if let existing = known.first(where: { $0.id == id }) { playlist = existing }
                        else {
                            let detail = try await KaraokeAPIClient.playlistDetail(id: id)
                            playlist = Playlist(id: id, name: detail.name, songCount: detail.songListDTOs.count, mosaicMedia: nil, songListDTOs: detail.songListDTOs)
                        }
                    }
                case .song(let id): song = try await KaraokeAPIClient.fetchSong(id: id)
                default: break
                }
            } catch { failed = true }
        }
    }
}
