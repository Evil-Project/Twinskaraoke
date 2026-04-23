import Foundation
import Combine

struct PhoneSong: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let duration: Int
    let absolutePath: String?
    let coverArt: PhoneMedia?
    let originalArtists: [String]?
    let coverArtists: [String]?

    struct PhoneMedia: Codable {
        let absolutePath: String
    }

    var imageURL: URL? {
        guard let path = coverArt?.absolutePath else { return nil }
        return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
    }

    var audioURL: URL? {
        guard let path = absolutePath else { return nil }
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "https://storage.neurokaraoke.com/" + encodedPath)
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

struct PhoneSearchResponse: Codable {
    let items: [PhoneSong]
}
