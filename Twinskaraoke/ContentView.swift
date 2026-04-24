import SwiftUI

struct ContentView: View {
    @StateObject var audioManager = AudioPlayerManager.shared
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                iPhoneHomeView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                
                iPhonePlaylistsView()
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                
                iPhoneSearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                
                NavigationStack {
                    List {
                        Section("User Info") {
                            Label("Profile", systemImage: "person.circle")
                            Label("Favorites", systemImage: "heart")
                        }
                    }
                    .navigationTitle("Account")
                }
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
            .accentColor(.pink)
            
            if audioManager.currentSong != nil {
                NowPlayingBar()
                    .offset(y: -49)
            }
        }
        .environmentObject(audioManager)
    }
}

#Preview {
    ContentView()
}
