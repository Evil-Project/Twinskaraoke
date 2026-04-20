//
//  MusicPlayerView.swift
//  Twinskaraoke
//
//  Created by xiaoyuan on 2026/4/19.
//

import AVFoundation
import Combine
import SwiftUI

enum PlaybackMode {
  case listLoop
  case singleLoop

  var iconName: String {
    switch self {
    case .listLoop: return "repeat"
    case .singleLoop: return "repeat.1"
    }
  }
}

class MusicPlayerViewModel: ObservableObject {
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  @Published var isPlaying = false
  @Published var currentTime: Double = 0
  @Published var duration: Double = 0
  @Published var isLoading = false
  @Published var playbackMode: PlaybackMode = .listLoop
  @Published var isShuffleOn = false
  @Published var isEditingTime = false
  let songs: [Song]
  @Published var currentIndex: Int
  var currentSong: Song {
    songs[currentIndex]
  }
  init(songs: [Song], initialIndex: Int) {
    self.songs = songs
    self.currentIndex = initialIndex
    prepareAndPlay()
  }
  private func prepareAndPlay() {
    player?.pause()
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }
    player = nil
    currentTime = 0
    duration = 0
    isPlaying = false
    cancellables.removeAll()
    guard let url = currentSong.audioURL else { return }
    isLoading = true
    setupPlayer(with: url)
  }
  private func setupPlayer(with url: URL) {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback, mode: .default, policy: .longFormAudio)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Audio Session Error: \(error)")
    }
    let playerItem = AVPlayerItem(url: url)
    self.player = AVPlayer(playerItem: playerItem)
    playerItem.publisher(for: \.duration)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] duration in
        let seconds = CMTimeGetSeconds(duration)
        if !seconds.isNaN && seconds > 0 {
          self?.duration = seconds
        }
      }
      .store(in: &cancellables)
    playerItem.publisher(for: \.status)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        if status == .readyToPlay {
          self?.isLoading = false
          self?.player?.play()
          self?.isPlaying = true
        } else if status == .failed {
          self?.isLoading = false
          print("Player item failed: \(String(describing: self?.player?.currentItem?.error))")
          self?.playNext()
        }
      }
      .store(in: &cancellables)
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      guard let self = self else { return }
      let seconds = CMTimeGetSeconds(time)
      if seconds.isFinite && !seconds.isNaN {
        self.currentTime = max(0, seconds)
      }
    }
    NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
    ) { [weak self] _ in
      self?.playEnded()
    }
  }
  func togglePlayPause() {
    if isPlaying {
      player?.pause()
    } else {
      player?.play()
    }
    isPlaying.toggle()
  }
  func playNext() {
    if isShuffleOn && songs.count > 1 {
      var nextIndex = currentIndex
      while nextIndex == currentIndex {
        nextIndex = Int.random(in: 0..<songs.count)
      }
      currentIndex = nextIndex
    } else {
      currentIndex = (currentIndex + 1) % songs.count
    }
    prepareAndPlay()
  }

  func playEnded() {
    if playbackMode == .singleLoop {
      player?.seek(to: .zero)
      player?.play()
    } else {
      playNext()
    }
  }

  func toggleMode() {
    switch playbackMode {
    case .listLoop: playbackMode = .singleLoop
    case .singleLoop: playbackMode = .listLoop
    }
  }
  func toggleShuffle() {
    isShuffleOn.toggle()
  }
  func playPrevious() {
    if currentTime > 3.0 {
      player?.seek(to: .zero)
    } else if currentIndex > 0 {
      currentIndex -= 1
      prepareAndPlay()
    } else {
      player?.seek(to: .zero)
    }
  }
  func seek(to time: Double) {
    player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
  }
  deinit {
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
    }
    player?.pause()
  }
}

struct MusicPlayerView: View {
  @StateObject var viewModel: MusicPlayerViewModel
  init(songs: [Song], initialIndex: Int) {
    _viewModel = StateObject(
      wrappedValue: MusicPlayerViewModel(songs: songs, initialIndex: initialIndex))
  }
  var body: some View {
    VStack(alignment: .center, spacing: 8) {
      ZStack {
        AsyncImage(url: viewModel.currentSong.imageURL) { image in
          image.resizable()
            .scaledToFill()
        } placeholder: {
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.3))
        }
        .frame(width: 48, height: 48)
        .cornerRadius(6)
        .clipped()

        if viewModel.isLoading {
          Color.black.opacity(0.3).cornerRadius(6)
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .pink))
            .scaleEffect(0.6)
        }
      }
      .frame(width: 48, height: 48)

      VStack(alignment: .center, spacing: 2) {
        Text(viewModel.currentSong.title)
          .font(.system(size: 14, weight: .bold))
          .lineLimit(1)
          .multilineTextAlignment(.center)
        Text(viewModel.currentSong.artistName)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 4)

      VStack(spacing: 6) {
        let totalDuration = max(viewModel.duration, 1)
        ProgressView(value: min(viewModel.currentTime, totalDuration), total: totalDuration)
          .progressViewStyle(LinearProgressViewStyle(tint: .pink))
          .frame(height: 2)

        HStack {
          Text(formatTime(viewModel.currentTime))
          Spacer()
          Text(formatTime(viewModel.duration))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.secondary)
      }
      .padding(.vertical, 2)

      HStack(spacing: 12) {
        Button(action: { viewModel.toggleMode() }) {
          Image(systemName: viewModel.playbackMode.iconName)
            .font(.system(size: 16))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 24)

        Button(action: { viewModel.playPrevious() }) {
          Image(systemName: "backward.fill")
            .font(.system(size: 20))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)

        Button(action: { viewModel.togglePlayPause() }) {
          Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 36))
            .foregroundColor(.pink)
        }
        .buttonStyle(.plain)

        Button(action: { viewModel.playNext() }) {
          Image(systemName: "forward.fill")
            .font(.system(size: 20))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)

        Button(action: { viewModel.toggleShuffle() }) {
          Image(systemName: "shuffle")
            .font(.system(size: 16))
            .foregroundColor(viewModel.isShuffleOn ? .pink : .secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 24)
      }
    }
    .padding(.horizontal, 4)
    .padding(.bottom, 32)
    .edgesIgnoringSafeArea(.bottom)
    .navigationTitle("Now Playing")
    .navigationBarTitleDisplayMode(.inline)
  }
  private func formatTime(_ time: Double) -> String {
    if time.isNaN || time.isInfinite { return "0:00" }
    let mins = Int(time) / 60
    let secs = Int(time) % 60
    return String(format: "%d:%02d", mins, secs)
  }
}
