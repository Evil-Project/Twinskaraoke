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
            Tab("Home", systemImage: "house.fill", value: TVTab.home) {
                HomeView(onPlay: play)
            }

            // No `.search` role: it only changes which tab hosts a
            // `.searchable` TabView, and SearchView owns its own field.
            Tab("Search", systemImage: "magnifyingglass", value: TVTab.search) {
                SearchView(onPlay: play)
            }

            Tab("Library", systemImage: "music.note.list", value: TVTab.library) {
                LibraryView(onPlay: play)
            }

            Tab("Playlists", systemImage: "list.bullet", value: TVTab.playlists) {
                PlaylistsView(onPlay: play)
            }

            Tab("Account", systemImage: "person.crop.circle", value: TVTab.account) {
                AccountView()
            }

            // "Playing", not "Now Playing": the tvOS tab bar is a fixed-width
            // pill, and a sixth tab pushes the last label past its right
            // edge, where it renders half-faded at rest.
            Tab("Playing", systemImage: "play.circle.fill", value: TVTab.nowPlaying) {
                PlayerView()
                    .accessibilityLabel("Now Playing")
            }
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
