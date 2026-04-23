import Combine
import Foundation
import SwiftUI

struct SearchSongItem: Codable, Identifiable {
    let id: String
    let title: String
    let originalArtists: [String]
    let coverArtists: [String]
    let coverArt: SearchMedia?
    
    var imageURL: URL? {
        guard let path = coverArt?.absolutePath else { return nil }
        return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
    }
    
    var originalArtistDisplay: String {
        originalArtists.joined(separator: ", ")
    }
    
    var coverArtistDisplay: String {
        let covers = coverArtists.map { $0.lowercased() }
        let hasNeuro = covers.contains(where: { $0.contains("neuro") })
        let hasEvil = covers.contains(where: { $0.contains("evil") })
        
        if hasNeuro && hasEvil { return "Neuro & Evil" }
        if hasEvil { return "Evil" }
        if hasNeuro { return "Neuro" }
        return coverArtists.first ?? ""
    }
}

struct SearchMedia: Codable {
    let absolutePath: String
}

struct SearchResponseRoot: Codable {
    let items: [SearchSongItem]
}

class SearchViewModel: ObservableObject {
    @Published var results: [SearchSongItem] = []
    @Published var isLoading = false
    @Published var searchText = ""
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                if !text.isEmpty {
                    self?.performSearch(query: text)
                } else {
                    self?.results = []
                }
            }
            .store(in: &cancellables)
    }
    
    func performSearch(query: String) {
        guard let url = URL(string: "https://api.neurokaraoke.com/api/songs") else { return }
        
        isLoading = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
        
        let body: [String: Any] = [
            "page": 1,
            "pageSize": 20,
            "search": query
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(SearchResponseRoot.self, from: data)
                DispatchQueue.main.async {
                    self.results = decoded.items
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }
}

struct SongSearchView: View {
    @StateObject var viewModel = SearchViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            TextField("Search...", text: $viewModel.searchText)
                .padding(8)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 4)
            
            List {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.results) { song in
                        NavigationLink(destination: Text(song.title)) {
                            HStack(spacing: 12) {
                                if let url = song.imageURL {
                                    AsyncImage(url: url) { image in
                                        image.resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.2)
                                    }
                                    .frame(width: 48, height: 48)
                                    .cornerRadius(6)
                                    .clipped()
                                } else {
                                    Image(systemName: "music.note")
                                        .frame(width: 48, height: 48)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(6)
                                }
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(song.title) - \(song.originalArtistDisplay)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    Text(song.coverArtistDisplay)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: MusicGridView()) {
                    Label("Playlists", systemImage: "music.note.list")
                }
                
                NavigationLink(destination: Text("Songs")) {
                    Label("Songs", systemImage: "music.note")
                }
                
                NavigationLink(destination: SongSearchView()) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                
                NavigationLink(destination: Text("Account")) {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
            .navigationTitle("Twins Karaoke")
        }
    }
}

#Preview {
    ContentView()
}
