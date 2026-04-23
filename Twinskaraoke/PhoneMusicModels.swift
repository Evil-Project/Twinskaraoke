// PhoneMusicModels.swift
import Foundation
import Combine

// Search Models
struct PhoneSong: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let duration: Int
    let absolutePath: String?
    let coverArt: Media?
    let originalArtists: [String]?
    let coverArtists: [String]?

    var imageURL: URL? {
        guard let path = coverArt?.absolutePath else { return nil }
        return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
    }

    var titleAndArtist: String {
        let artist = originalArtists?.joined(separator: ", ") ?? "Unknown Artist"
        return "\(title) - \(artist)"
    }

    var singerIdentity: String {
        let covers = coverArtists?.map { $0.lowercased() } ?? []
        if covers.contains(where: { $0.contains("neuro") }) && covers.contains(where: { $0.contains("evil") }) {
            return "Neuro & Evil"
        } else if covers.contains(where: { $0.contains("evil") }) {
            return "Evil"
        } else if covers.contains(where: { $0.contains("neuro") }) {
            return "Neuro"
        }
        return coverArtists?.first ?? "Cover"
    }

    static func == (lhs: PhoneSong, rhs: PhoneSong) -> Bool { lhs.id == rhs.id }
}

struct PhoneSearchResponse: Codable {
    let items: [PhoneSong]
}

// Playlist Models
struct Playlist: Codable, Identifiable {
    let id: String
    let name: String
    let songCount: Int
    let mosaicMedia: [Media]?
    
    var imageURL: URL? {
        guard let path = mosaicMedia?.first?.absolutePath else { return nil }
        return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
    }
}

struct Media: Codable {
    let absolutePath: String
}

class PhoneSearchViewModel: ObservableObject {
    @Published var results: [PhoneSong] = []
    @Published var isLoading = false
    @Published var searchText = ""
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                if !text.isEmpty { self?.search(query: text) }
                else { self?.results = [] }
            }
            .store(in: &cancellables)
    }
    
    func search(query: String) {
        guard let url = URL(string: "https://api.neurokaraoke.com/api/songs") else { return }
        isLoading = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
        
        let body: [String: Any] = ["page": 1, "pageSize": 30, "search": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data, let decoded = try? JSONDecoder().decode(PhoneSearchResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.results = decoded.items
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }
}

class PhonePlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false
    
    func fetchPlaylists() {
        let urlString = "https://api.neurokaraoke.com/api/playlists?startIndex=0&pageSize=25&search=&sortBy=&sortDescending=False&isSetlist=True&year=0"
        guard let url = URL(string: urlString) else { return }
        
        isLoading = true
        var request = URLRequest(url: url)
        request.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let data = data {
                    if let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
                        self.playlists = decoded
                    }
                }
            }
        }.resume()
    }
}
