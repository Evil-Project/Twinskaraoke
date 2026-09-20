import SwiftUI

enum TVTab: Hashable {
    case home
    case search
    case library
    case playlists
    case account
    case nowPlaying
}

struct ContentView: View {
    private let audioManager = AudioManager.shared
    @State private var selectedTab: TVTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onPlay: play)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(TVTab.home)

            SearchView(onPlay: play)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(TVTab.search)

            LibraryView(onPlay: play)
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(TVTab.library)

            PlaylistsView(onPlay: play)
                .tabItem { Label("Playlists", systemImage: "list.bullet") }
                .tag(TVTab.playlists)

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(TVTab.account)

            PlayerView()
                .tabItem { Label("Playing", systemImage: "play.circle.fill") }
                .tag(TVTab.nowPlaying)
                .accessibilityLabel("Now Playing")
        }
        .environment(audioManager)
        .tint(.appAccent)
        .injectReduceMotion()
    }
    private func play(_ song: Song, context: [Song]) {
        audioManager.play(song: song, context: context)
        selectedTab = .nowPlaying
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
