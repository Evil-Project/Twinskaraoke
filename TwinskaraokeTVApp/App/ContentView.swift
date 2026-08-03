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
                // "Playing", not "Now Playing": the tvOS tab bar is a
                // fixed-width pill, and a sixth tab pushes the last label past
                // its right edge, where it renders half-faded at rest.
                .tabItem { Label("Playing", systemImage: "play.circle.fill") }
                .tag(TVTab.nowPlaying)
                .accessibilityLabel("Now Playing")
        }
        .environment(audioManager)
        .tint(.appAccent)
        // The lyrics panel reads `\.appReduceMotion` for its scroll and
        // depth-of-field animations, same as iOS; without this it would always
        // see the environment default.
        .injectReduceMotion()
    }

    /// Plays a song within its list context and jumps to the full-screen player.
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
