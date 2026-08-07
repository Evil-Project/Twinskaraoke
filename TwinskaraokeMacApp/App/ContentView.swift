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
        // Account belongs in the window toolbar, not the sidebar list: the
        // Playlists section grows without bound, and a sidebar row below it
        // scrolls out of reach as soon as the user has a dozen playlists.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selection = .account
                } label: {
                    AccountToolbarIcon(auth: auth)
                }
                .help(auth.isLoggedIn ? (auth.username ?? "Account") : "Sign in to Twinskaraoke")
                .accessibilityLabel(auth.isLoggedIn ? (auth.username ?? "Account") : "Sign In")
            }
        }
        .environment(auth)
        .task {
            await playlists.loadIfNeeded()
            FavoritesManager.shared.loadIfNeeded()
            await auth.refreshAccount()
        }
        // This .task runs once for the window's lifetime, so signing in or out
        // would otherwise leave the sidebar showing the previous user's
        // playlists (or the public fallback) until a manual refresh.
        .onChange(of: auth.isLoggedIn) { _, _ in
            playlists.invalidate()
            Task {
                await playlists.reload()
                await auth.refreshAccount()
            }
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
                    // Previously this section just rendered nothing, making a
                    // failed load indistinguishable from an empty account.
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
            // Refresh lives here rather than in the toolbar: macOS merges the
            // sidebar and detail toolbars into one window toolbar, so a second
            // arrow.clockwise button sat next to the detail view's own refresh.
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
                // Rebuild the view (and its view model) when the selection
                // moves to a different playlist.
                .id(id)
        case .account:
            AccountView()
        }
    }
}
