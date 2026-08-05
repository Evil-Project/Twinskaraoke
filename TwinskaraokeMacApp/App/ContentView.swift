import SwiftUI

enum MacDestination: Hashable {
    case home
    case search
    case favorites
    case playlist(id: String, name: String)
    case account
}

struct ContentView: View {
    @Environment(MacAudioManager.self) private var audio
    @State private var auth = MacAuthManager.shared
    @State private var playlists = MacPlaylistsViewModel()
    @State private var selection: MacDestination? = .home

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The player bar spans the whole window rather than living inside the
        // detail pane — the Music.app arrangement, and the reason this reads as
        // a Mac app instead of a resized iPad one.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
        }
        .environment(auth)
        .task {
            await playlists.loadIfNeeded()
            FavoritesManager.shared.loadIfNeeded()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house")
                    .tag(MacDestination.home)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(MacDestination.search)
                Label("Favourites", systemImage: "heart")
                    .tag(MacDestination.favorites)
            }

            Section("Playlists") {
                if playlists.isLoading && playlists.playlists.isEmpty {
                    ProgressView().controlSize(.small)
                }
                ForEach(playlists.playlists) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .tag(MacDestination.playlist(id: playlist.id, name: playlist.name))
                }
            }

            Section {
                Label(auth.isLoggedIn ? (auth.username ?? "Account") : "Sign In",
                      systemImage: "person.crop.circle")
                    .tag(MacDestination.account)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await playlists.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh playlists")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home, nil:
            HomeView()
        case .search:
            SearchView()
        case .favorites:
            FavoritesView()
        case .playlist(let id, let name):
            PlaylistDetailView(playlistID: id, playlistName: name)
                // Rebuild the view (and its view model) when the selection
                // moves to a different playlist.
                .id(id)
        case .account:
            AccountView()
        }
    }
}
