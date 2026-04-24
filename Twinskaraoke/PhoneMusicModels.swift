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

    var fullDisplayTitle: String {
        let artists = originalArtists?.joined(separator: ", ") ?? ""
        return artists.isEmpty ? title : "\(title) - \(artists)"
    }
    
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

    var displayTitle: String {
        let artists = originalArtists?.joined(separator: ", ") ?? ""
        let full = artists.isEmpty ? title : "\(title) - \(artists)"
        return full.count > 20 ? String(full.prefix(20)) + "…" : full
    }

    var displayCoverArtist: String {
        coverArtists?.joined(separator: ", ") ?? ""
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
                        Rectangle().fill(Color.white.opacity(0.1))
                        Rectangle()
                            .fill(Color.pink)
                            .frame(width: geo.size.width * CGFloat(audioManager.progress))
                    }
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    LoadingImage(url: song.imageURL, cornerRadius: 6)
                        .frame(width: 44, height: 44)
                        .clipped()
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: song.fullDisplayTitle, font: .system(size: 20, weight: .bold), color: .white)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if !song.displayCoverArtist.isEmpty {
                            Text(song.displayCoverArtist)
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    HStack(spacing: 18) {
                        Button { audioManager.playPrevious() } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                        Button { audioManager.togglePlayPause() } label: {
                            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 22)
                        }
                        Button { audioManager.playNextOrRandom() } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(white: 0.1))
            }
            .onTapGesture { audioManager.showFullScreen = true }
            .fullScreenCover(isPresented: $audioManager.showFullScreen) {
                FullScreenPlayerView().environmentObject(audioManager)
            }
        }
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    
    @State private var animate = false
    @State private var textWidth: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .overlay(
                GeometryReader { geo in
                    let needsScroll = textWidth > geo.size.width
                    
                    if needsScroll {
                        Text(text + "          " + text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize()
                            .offset(x: animate ? -(textWidth + 80) : 0)
                            .animation(
                                .linear(duration: Double(textWidth) / 30)
                                .delay(1.0)
                                .repeatForever(autoreverses: false),
                                value: animate
                            )
                            .onAppear { animate = true }
                    } else {
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )
            .background(
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .background(GeometryReader { t in
                        Color.clear.preference(key: TextWidthKey.self, value: t.size.width)
                    })
            )
            .onPreferenceChange(TextWidthKey.self) { w in
                textWidth = w
            }
            .clipped()
    }
}
private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct FullScreenPlayerView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    private let pad: CGFloat = 36

    var body: some View {
        if let song = audioManager.currentSong {
            let artSize = UIScreen.main.bounds.width - (pad * 2)
            ZStack {
                LoadingImage(url: song.imageURL, cornerRadius: 0)
                    .ignoresSafeArea()
                    .blur(radius: 70)
                    .scaleEffect(1.4)
                    .opacity(0.45)
                Color.black.opacity(0.6).ignoresSafeArea()

                SafeAreaPaddedPlayer(
                    song: song,
                    artSize: artSize,
                    pad: pad,
                    audioManager: audioManager,
                    dismiss: dismiss
                )
            }
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct SafeAreaPaddedPlayer: View {
    let song: PhoneSong
    let artSize: CGFloat
    let pad: CGFloat
    let audioManager: AudioPlayerManager
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                Spacer()
                Text("Now Playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button {} label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, pad)
            .padding(.top, 16)

            Spacer()

            LoadingImage(url: song.imageURL, cornerRadius: 20, contentMode: .fit)
                .frame(width: artSize, height: artSize)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)

            Spacer()

            VStack(spacing: 20) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        MarqueeText(text: song.fullDisplayTitle, font: .system(size: 20, weight: .bold), color: .white)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if !song.displayCoverArtist.isEmpty {
                            Text(song.displayCoverArtist)
                                .font(.system(size: 15))
                                .foregroundColor(Color.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {} label: {
                        Image(systemName: "heart")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, pad)

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { audioManager.progress },
                            set: { audioManager.seek(to: $0) }
                        )
                    )
                    .accentColor(.pink)
                    .padding(.horizontal, pad)

                    HStack {
                        Text(formattedTime(audioManager.progress * Double(song.duration)))
                        Spacer()
                        Text(formattedTime(Double(song.duration)))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(.horizontal, pad + 4)
                }

                HStack(spacing: 0) {
                    Button { audioManager.playPrevious() } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                    }
                    Button { audioManager.togglePlayPause() } label: {
                        ZStack {
                            Circle()
                                .fill(Color.pink)
                                .frame(width: 70, height: 70)
                            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                                .offset(x: audioManager.isPlaying ? 0 : 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Button { audioManager.playNextOrRandom() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, pad)
            }
            .padding(.bottom, 48)
        }
        .padding(.top, safeAreaTop())
    }

    private func formattedTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func safeAreaTop() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 44
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
