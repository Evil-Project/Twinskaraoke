import SwiftUI

enum MacDestination: Hashable {
    case home
    case search
    case library
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
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            PlayerBar()
                .fixedSize(horizontal: false, vertical: true)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selection = .account
                } label: {
                    AccountToolbarIcon(auth: auth)
                }
                .help(auth.isLoggedIn ? (auth.username ?? String(localized: "Account")) : "Sign in to Twinskaraoke")
                .accessibilityLabel(auth.isLoggedIn ? (auth.username ?? String(localized: "Account")) : "Sign In")
            }
        }
        .environment(auth)
        .task {
            FavoritesManager.shared.loadIfNeeded()
        }
        .task(id: auth.isLoggedIn) {
            playlists.invalidate()
            guard auth.isLoggedIn else { return }
            async let playlistLoad: Void = playlists.reload()
            async let accountRefresh: Void = auth.refreshAccount()
            _ = await (playlistLoad, accountRefresh)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house")
                    .tag(MacDestination.home)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(MacDestination.search)
                Label("Library", systemImage: "books.vertical")
                    .tag(MacDestination.library)
                Label("Favourites", systemImage: "heart")
                    .tag(MacDestination.favorites)
            }

            Section("Playlists") {
                if !auth.isLoggedIn {
                    Text("Sign in to see your playlists")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if playlists.isLoading && playlists.playlists.isEmpty {
                    ProgressView().controlSize(.small)
                } else if playlists.playlists.isEmpty, playlists.errorMessage == nil {
                    Text("No playlists yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if playlists.playlists.isEmpty, let error = playlists.errorMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await playlists.reload() }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
                ForEach(playlists.playlists) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .tag(MacDestination.playlist(id: playlist.id, name: playlist.name))
                }
            }
            .contextMenu {
                Button("Refresh Playlists") {
                    Task { await playlists.reload() }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home, nil:
            HomeView()
        case .search:
            SearchView()
        case .library:
            LibraryView(selection: $selection)
        case .favorites:
            FavoritesView()
        case .playlist(let id, let name):
            PlaylistDetailView(playlistID: id, playlistName: name)
                .id(id)
        case .account:
            AccountView()
        }
    }
}
