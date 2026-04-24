import Foundation
import SwiftUI
import AVFoundation
import Combine

class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    
    @Published var currentSong: PhoneSong?
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var queue: [PhoneSong] = []
    @Published var showFullScreen = false
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in self?.playNextOrRandom() }
            .store(in: &cancellables)
    }
    
    func play(song: PhoneSong, context: [PhoneSong] = []) {
        currentSong = song
        if !context.isEmpty { queue = context }
        
        guard let url = song.audioURL else { return }
        let playerItem = AVPlayerItem(url: url)
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
            setupTimeObserver()
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        player?.play()
        isPlaying = true
    }
    
    func togglePlayPause() {
        if isPlaying { player?.pause() } else { player?.play() }
        isPlaying.toggle()
    }
    
    func playNextOrRandom() {
        if let current = currentSong, !queue.isEmpty, let idx = queue.firstIndex(of: current), idx + 1 < queue.count {
            play(song: queue[idx + 1])
        } else {
            fetchRandomTrending()
        }
    }
    
    func playPrevious() {
        if let current = currentSong, !queue.isEmpty, let idx = queue.firstIndex(of: current), idx - 1 >= 0 {
            play(song: queue[idx - 1])
        } else {
            seek(to: 0)
        }
    }
    
    func seek(to percentage: Double) {
        guard let duration = player?.currentItem?.duration.seconds, duration.isFinite else { return }
        player?.seek(to: CMTime(seconds: duration * percentage, preferredTimescale: 600))
    }
    
    private func setupTimeObserver() {
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self, let duration = self.player?.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
            self.progress = time.seconds / duration
        }
    }
    
    private func fetchRandomTrending() {
        guard let url = URL(string: "https://api.neurokaraoke.com/api/explore/trendings?days=7&take=50") else { return }
        var request = URLRequest(url: url)
        request.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data, let songs = try? JSONDecoder().decode([PhoneSong].self, from: data), let random = songs.randomElement() {
                DispatchQueue.main.async { self.play(song: random, context: songs) }
            }
        }.resume()
    }
}
