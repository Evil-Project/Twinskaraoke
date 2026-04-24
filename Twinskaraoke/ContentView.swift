import SwiftUI

struct ContentView: View {
    @StateObject var audioManager = AudioPlayerManager.shared

    var body: some View {
        TabView {
            iPhoneHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            iPhonePlaylistsView()
                .tabItem { Label("Library", systemImage: "music.note.list") }
            iPhoneSearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .accentColor(.pink)
        .overlay(alignment: .bottom) {
            if audioManager.currentSong != nil {
                NowPlayingBar()
                    .padding(.bottom, 49)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: audioManager.currentSong != nil)
            }
        }
        .environmentObject(audioManager)
    }
}

#Preview {
    ContentView()
}
