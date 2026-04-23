// ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                VStack {
                    Image(systemName: "house.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.pink.opacity(0.8))
                    Text("Welcome Home")
                        .font(.headline)
                        .padding(.top)
                }
                .navigationTitle("Home")
            }
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
    }
}

#Preview {
    ContentView()
}
