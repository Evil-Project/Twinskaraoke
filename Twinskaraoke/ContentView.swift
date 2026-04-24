import SwiftUI

struct ContentView: View {
    @StateObject var audioManager = AudioPlayerManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                iPhoneHomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }

                iPhonePlaylistsView()
                    .tabItem { Label("Library", systemImage: "music.note.list") }

                iPhoneSearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
            }
            .accentColor(.pink)

            if audioManager.currentSong != nil {
                NowPlayingBar()
                    .padding(.bottom, 49)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: audioManager.currentSong != nil)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .environmentObject(audioManager)
    }
}

#Preview {
    ContentView()
}
