import SwiftUI

struct HomeView: View {
    @State private var model = BrowseViewModel()

    var body: some View {
        Group {
            if model.isLoading && model.trending.isEmpty && model.latest.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, model.trending.isEmpty, model.latest.isEmpty {
                StateMessage(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't load Home",
                    subtitle: error
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !model.trending.isEmpty {
                            SongShelf(title: "Trending This Week", songs: model.trending)
                        }
                        if !model.latest.isEmpty {
                            SongShelf(title: "Latest Releases", songs: model.latest)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .task { await model.loadIfNeeded() }
    }
}

struct SearchView: View {
    @State private var model = MacSearchViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search songs or artists", text: Bindable(model).query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onChange(of: model.query) { _, _ in model.queryChanged() }
                if !model.query.isEmpty {
                    Button { model.clear() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if model.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(16)

            Divider()

            content
        }
        .navigationTitle("Search")
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.errorMessage {
            StateMessage(systemImage: "exclamationmark.triangle", title: "Search failed", subtitle: error)
        } else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            StateMessage(
                systemImage: "magnifyingglass",
                title: "Search Twinskaraoke",
                subtitle: "Type at least two characters to find songs."
            )
        } else if model.results.isEmpty && !model.isSearching {
            StateMessage(systemImage: "questionmark.circle", title: "No results")
        } else {
            List(model.results) { song in
                SongRow(song: song, context: model.results)
            }
            .listStyle(.inset)
        }
    }
}

struct FavoritesView: View {
    @State private var model = MacFavoritesViewModel()
    @Environment(MacAuthManager.self) private var auth

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                StateMessage(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "Sign in to see favourites",
                    subtitle: "Your favourites sync with your Twinskaraoke account."
                )
            } else if model.isLoading && model.songs.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, model.songs.isEmpty {
                StateMessage(systemImage: "exclamationmark.triangle", title: "Couldn't load", subtitle: error)
            } else if model.songs.isEmpty {
                StateMessage(
                    systemImage: "heart",
                    title: "No favourites yet",
                    subtitle: "Songs you favourite will show up here."
                )
            } else {
                List(model.songs) { song in
                    SongRow(song: song, context: model.songs)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Favourites")
        .task { if auth.isLoggedIn { await model.reload() } }
    }
}

struct PlaylistDetailView: View {
    let playlistID: String
    let playlistName: String

    @State private var model = MacPlaylistDetailViewModel()

    var body: some View {
        Group {
            if model.isLoading && model.songs.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, model.songs.isEmpty {
                StateMessage(systemImage: "exclamationmark.triangle", title: "Couldn't load", subtitle: error)
            } else if model.songs.isEmpty {
                StateMessage(systemImage: "music.note.list", title: "This playlist is empty")
            } else {
                List(model.songs) { song in
                    SongRow(song: song, context: model.songs)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(playlistName)
        .task { await model.load(playlistID: playlistID) }
    }
}
