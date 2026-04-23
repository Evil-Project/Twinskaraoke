import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                VStack {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("Playlists coming soon")
                        .foregroundColor(.secondary)
                }
                .navigationTitle("Playlists")
            }
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
    }
}

#Preview {
    ContentView()
}
