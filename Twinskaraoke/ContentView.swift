import SwiftUI

struct NowPlayingBarContainer: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    if audioManager.currentSong != nil {
      NowPlayingBar()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(
          .spring(response: 0.4, dampingFraction: 0.75), value: audioManager.currentSong != nil)
    }
  }
}

struct ContentView: View {
  @StateObject var audioManager = AudioPlayerManager.shared
  var body: some View {
    TabView {
      iPhoneHomeView()
        .safeAreaInset(edge: .bottom) { NowPlayingBarContainer() }
        .tabItem { Label("Home", systemImage: "house.fill") }
      iPhonePlaylistsView()
        .safeAreaInset(edge: .bottom) { NowPlayingBarContainer() }
        .tabItem { Label("Library", systemImage: "music.note.list") }
      iPhoneSearchView()
        .safeAreaInset(edge: .bottom) { NowPlayingBarContainer() }
        .tabItem { Label("Search", systemImage: "magnifyingglass") }
    iPhoneAccountView()
        .safeAreaInset(edge: .bottom) { NowPlayingBarContainer() }
        .tabItem { Label("Account", systemImage: "person") }
    }
    .accentColor(.pink)
    .fullScreenCover(isPresented: $audioManager.showFullScreen) {
      FullScreenPlayerView()
        .environmentObject(audioManager)
    }
    .environmentObject(audioManager)
  }
}

#Preview {
  ContentView()
}
