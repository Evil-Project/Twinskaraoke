//
//  AudioPlayerManager.swift
//  Twinskaraoke
//
//  Created by Sebastian Reid on 24/4/2026.
//


import SwiftUI
import AVFoundation
import Combine

class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    
    @Published var currentSong: PhoneSong?
    @Published var isPlaying = false
    private var player: AVPlayer?
    
    func play(song: PhoneSong) {
        currentSong = song
        guard let url = song.audioURL else { return }
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        isPlaying = true
    }
    
    func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    
    var body: some View {
        if let song = audioManager.currentSong {
            HStack(spacing: 12) {
                AsyncImage(url: song.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 48, height: 48)
                .cornerRadius(6)
                .clipped()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Text(song.originalArtists?.joined(separator: ", ") ?? "Unknown")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: {
                    audioManager.togglePlayPause()
                }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .padding(.trailing, 8)
            }
            .padding(8)
            .background(Color(.systemBackground).opacity(0.95))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.2)),
                alignment: .top
            )
            .onTapGesture {
            }
        }
    }
}
