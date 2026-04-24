import Foundation
import SwiftUI
import AVFoundation
import Combine

struct PhoneSong: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let duration: Int
    let absolutePath: String?
    let cloudflareId: String?
    let coverArt: Media?
    let originalArtists: [String]?
    let coverArtists: [String]?

    var imageURL: URL? {
        if let cfId = cloudflareId {
            return URL(string: "https://images.neurokaraoke.com/\(cfId)/public")
        }
        guard let path = coverArt?.absolutePath else { return nil }
        return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
    }

    var audioURL: URL? {
        guard let path = absolutePath else { return nil }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "https://storage.neurokaraoke.com/\(cleanPath)")
    }

    static func == (lhs: PhoneSong, rhs: PhoneSong) -> Bool { lhs.id == rhs.id }
}

struct Playlist: Codable, Identifiable {
    let id: String
    let name: String
    let songCount: Int
    let mosaicMedia: [Media]?
    let songListDTOs: [PhoneSong]?

    var imageURL: URL? {
        guard let path = mosaicMedia?.first?.absolutePath else { return nil }
        return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
    }
}

struct Media: Codable {
    let absolutePath: String
}

struct PhoneSearchResponse: Codable {
    let items: [PhoneSong]
}

struct NowPlayingBar: View {
    @EnvironmentObject var audioManager: AudioPlayerManager

    var body: some View {
        if let song = audioManager.currentSong {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 2)
                        Rectangle()
                            .fill(Color.pink)
                            .frame(width: geo.size.width * CGFloat(audioManager.progress), height: 2)
                    }
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    LoadingImage(url: song.imageURL, cornerRadius: 6)
                        .frame(width: 44, height: 44)
                        .clipped()
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(song.originalArtists?.joined(separator: ", ") ?? "Unknown")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 20) {
                        Button {
                            audioManager.playPrevious()
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }

                        Button {
                            audioManager.togglePlayPause()
                        } label: {
                            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 24)
                        }

                        Button {
                            audioManager.playNextOrRandom()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        Color(white: 0.1)
                        Color.pink.opacity(0.08)
                    }
                )
                .cornerRadius(14)
                .padding(.horizontal, 8)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: -2)
            }
            .onTapGesture { audioManager.showFullScreen = true }
            .fullScreenCover(isPresented: $audioManager.showFullScreen) {
                FullScreenPlayerView()
                    .environmentObject(audioManager)
            }
        }
    }
}

struct FullScreenPlayerView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        if let song = audioManager.currentSong {
            ZStack {
                LoadingImage(url: song.imageURL, cornerRadius: 0)
                    .ignoresSafeArea()
                    .blur(radius: 60)
                    .scaleEffect(1.3)
                    .opacity(0.5)

                Color.black.opacity(0.55).ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }

                        Spacer()

                        Text("Now Playing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    Spacer()

                    LoadingImage(url: song.imageURL, cornerRadius: 16)
                        .frame(width: 300, height: 300)
                        .clipped()
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
                        .padding(.bottom, 36)

                    VStack(spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(song.originalArtists?.joined(separator: ", ") ?? "Unknown")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.white.opacity(0.65))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                            } label: {
                                Image(systemName: "heart")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 28)

                        VStack(spacing: 6) {
                            Slider(
                                value: Binding(
                                    get: { audioManager.progress },
                                    set: { audioManager.seek(to: $0) }
                                )
                            )
                            .accentColor(.pink)
                            .padding(.horizontal, 28)

                            HStack {
                                Text(formattedTime(audioManager.progress * Double(song.duration)))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.5))
                                Spacer()
                                Text(formattedTime(Double(song.duration)))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.5))
                            }
                            .padding(.horizontal, 30)
                        }

                        HStack(spacing: 0) {
                            Button {
                                audioManager.playPrevious()
                            } label: {
                                Image(systemName: "backward.end.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                audioManager.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.pink)
                                        .frame(width: 72, height: 72)
                                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                        .offset(x: audioManager.isPlaying ? 0 : 2)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                audioManager.playNextOrRandom()
                            } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer()
                }
            }
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

class HomeViewModel: ObservableObject {
    @Published var trending: [PhoneSong] = []
    @Published var suggestions: [PhoneSong] = []
    @Published var recentPlaylist: Playlist?
    @Published var isLoading = false

    func fetchHomeData() {
        isLoading = true
        let group = DispatchGroup()
        group.enter()
        fetchData(url: "https://api.neurokaraoke.com/api/explore/trendings?days=7&take=20") { (i: [PhoneSong]?) in
            if let i = i { DispatchQueue.main.async { self.trending = i } }
            group.leave()
        }
        group.enter()
        fetchData(url: "https://api.neurokaraoke.com/api/user/suggestions?take=20") { (i: [PhoneSong]?) in
            if let i = i { DispatchQueue.main.async { self.suggestions = i } }
            group.leave()
        }
        group.enter()
        fetchData(url: "https://api.neurokaraoke.com/api/playlist/recent") { (i: Playlist?) in
            if let i = i { DispatchQueue.main.async { self.recentPlaylist = i } }
            group.leave()
        }
        group.notify(queue: .main) { self.isLoading = false }
    }

    private func fetchData<T: Codable>(url: String, completion: @escaping (T?) -> Void) {
        guard let u = URL(string: url) else { completion(nil); return }
        var r = URLRequest(url: u)
        r.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
        URLSession.shared.dataTask(with: r) { d, _, _ in
            if let d = d, let dec = try? JSONDecoder().decode(T.self, from: d) { completion(dec) } else { completion(nil) }
        }.resume()
    }
}

class PhonePlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false

    func fetchPlaylists() {
        guard let url = URL(string: "https://api.neurokaraoke.com/api/playlists?startIndex=0&pageSize=25&search=&sortBy=&sortDescending=False&isSetlist=True&year=0") else { return }
        isLoading = true
        var r = URLRequest(url: url)
        r.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
        URLSession.shared.dataTask(with: r) { d, _, _ in
            if let d = d, let dec = try? JSONDecoder().decode([Playlist].self, from: d) {
                DispatchQueue.main.async { self.playlists = dec; self.isLoading = false }
            } else {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }
}

class PhoneSearchViewModel: ObservableObject {
    @Published var results: [PhoneSong] = []
    @Published var searchText = ""
    @Published var isSearching = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] t in
                if !t.isEmpty { self?.search(t) } else { self?.results = [] }
            }
            .store(in: &cancellables)
    }

    func search(_ q: String) {
        guard let u = URL(string: "https://api.neurokaraoke.com/api/songs") else { return }
        isSearching = true
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["page": 1, "pageSize": 30, "search": q])
        URLSession.shared.dataTask(with: r) { d, _, _ in
            if let d = d, let dec = try? JSONDecoder().decode(PhoneSearchResponse.self, from: d) {
                DispatchQueue.main.async { self.results = dec.items; self.isSearching = false }
            } else {
                DispatchQueue.main.async { self.isSearching = false }
            }
        }.resume()
    }
}
