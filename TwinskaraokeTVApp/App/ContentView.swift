import SwiftUI

enum TVTab: Hashable {
    case home
    case search
    case library
    case account
    case nowPlaying
}

struct ContentView: View {
    @StateObject private var audioManager = AudioManager.shared
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

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(TVTab.account)

            PlayerView()
                .tabItem { Label("Now Playing", systemImage: "play.circle.fill") }
                .tag(TVTab.nowPlaying)
        }
        .environmentObject(audioManager)
        .tint(.appAccent)
        // The lyrics panel reads `\.appReduceMotion` for its scroll and
        // depth-of-field animations, same as iOS; without this it would always
        // see the environment default.
        .injectReduceMotion()
    }

    /// Plays a song within its list context and jumps to the full-screen player.
    private func play(_ song: Song, context: [Song]) {
        if audioManager.currentSong?.id != song.id {
            audioManager.play(song: song, context: context)
        }
        selectedTab = .nowPlaying
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
