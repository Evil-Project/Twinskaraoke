//
//  MusicPlayerView.swift
//  Twinskaraoke
//
//  Created by xiaoyuan on 2026/4/19.
//
import AVFoundation
import Combine
import MediaPlayer
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
  private var endTimeObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var downloadTask: URLSessionDownloadTask?
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

  private static let audioCacheDir: URL = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("AudioCache")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  private func localCacheURL(for songID: String) -> URL {
    MusicPlayerViewModel.audioCacheDir.appendingPathComponent("\(songID).mp3")
  }

  init(songs: [Song], initialIndex: Int) {
    self.songs = songs
    self.currentIndex = initialIndex
    setupRemoteCommands()
    setupInterruptionHandler()
    prepareAndPlay()
  }
  private func setupInterruptionHandler() {
    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .sink { [weak self] note in self?.handleInterruption(note) }
      .store(in: &cancellables)
  }
  private func handleInterruption(_ note: Notification) {
    guard let info = note.userInfo,
      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }
    switch type {
    case .began:
      if isPlaying {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
      }
    case .ended:
      guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
      let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
      if opts.contains(.shouldResume) {
        do {
          try AVAudioSession.sharedInstance().setActive(true)
        } catch {
          print("Failed to reactivate audio session: \(error)")
        }
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
      }
    @unknown default: break
    }
  }
  private func setupRemoteCommands() {
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.addTarget { [weak self] _ in
      guard let self = self, !self.isPlaying else { return .commandFailed }
      self.togglePlayPause()
      return .success
    }
    cc.pauseCommand.addTarget { [weak self] _ in
      guard let self = self, self.isPlaying else { return .commandFailed }
      self.togglePlayPause()
      return .success
    }
    cc.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.togglePlayPause()
      return .success
    }
    cc.nextTrackCommand.addTarget { [weak self] _ in
      self?.playNext()
      return .success
    }
    cc.previousTrackCommand.addTarget { [weak self] _ in
      self?.playPrevious()
      return .success
    }
  }
  private func prepareAndPlay() {
    player?.pause()
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }
    if let observer = endTimeObserver {
      NotificationCenter.default.removeObserver(observer)
      endTimeObserver = nil
    }
    player = nil
    currentTime = 0
    duration = 0
    isPlaying = false
    cancellables.removeAll()
    setupInterruptionHandler()
    downloadTask?.cancel()

    let localURL = localCacheURL(for: currentSong.id)
    if FileManager.default.fileExists(atPath: localURL.path) {
      setupPlayer(with: localURL)
      return
    }

    guard let remoteURL = currentSong.audioURL else { return }
    isLoading = true
    downloadTask = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, _, error in
      DispatchQueue.main.async {
        self?.isLoading = false
        guard let self = self, let tempURL = tempURL, error == nil else { return }
        try? FileManager.default.moveItem(at: tempURL, to: localURL)
        guard self.currentSong.id == self.songs[self.currentIndex].id else { return }
        self.setupPlayer(with: localURL)
      }
    }
    downloadTask?.resume()
  }

  private func setupPlayer(with localURL: URL) {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback, mode: .default, policy: .longFormAudio)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Audio Session Error: \(error)")
    }
    let playerItem = AVPlayerItem(url: localURL)
    self.player = AVPlayer(playerItem: playerItem)
    if #available(watchOS 8.0, *) {
      self.player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }
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
          self?.updateNowPlayingInfo()

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
    if let oldObserver = endTimeObserver {
      NotificationCenter.default.removeObserver(oldObserver)
    }
    endTimeObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
    ) { [weak self] _ in
      self?.playEnded()
    }
  }
  private func updateNowPlayingInfo() {
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = currentSong.title
    info[MPMediaItemPropertyArtist] = currentSong.artistName
    info[MPMediaItemPropertyPlaybackDuration] = Double(duration)
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  func togglePlayPause() {
    if isPlaying {
      player?.pause()

    } else {
      do {
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        print("Failed to reactivate audio session: \(error)")
      }
      player?.play()
    }
    isPlaying.toggle()
    updateNowPlayingInfo()
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
    updateNowPlayingInfo()
  }
  deinit {
    downloadTask?.cancel()
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
    }
    if let observer = endTimeObserver {
      NotificationCenter.default.removeObserver(observer)
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
    ZStack {
      if let url = viewModel.currentSong.imageURL {
        AsyncImage(url: url) { image in
          image.resizable()
            .scaledToFill()
        } placeholder: {
          Color.black
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .blur(radius: 20)
        .opacity(0.4)
        .ignoresSafeArea()
      } else {
        Color.black.ignoresSafeArea()
      }

      VStack(alignment: .center, spacing: 4) {
        ZStack {
          AsyncImage(url: viewModel.currentSong.imageURL) { image in
            image.resizable()
              .scaledToFill()
          } placeholder: {
            RoundedRectangle(cornerRadius: 6)
              .fill(Color.secondary.opacity(0.25))
          }
          .frame(width: 56, height: 56)
          .cornerRadius(6)
          .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
          if viewModel.isLoading {
            Color.black.opacity(0.3).cornerRadius(6)
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .pink))
              .scaleEffect(0.6)
          }
        }
        .frame(width: 56, height: 56)
        .padding(.top, 4)

        VStack(alignment: .center, spacing: 0) {
          Text(viewModel.currentSong.title)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
            .multilineTextAlignment(.center)
          Text(viewModel.currentSong.artistName)
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.7))
            .lineLimit(1)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)

        VStack(spacing: 2) {
          let totalDuration = max(viewModel.duration, 1)
          ProgressView(value: min(viewModel.currentTime, totalDuration), total: totalDuration)
            .progressViewStyle(LinearProgressViewStyle(tint: .white.opacity(0.8)))
            .frame(height: 2)
          HStack {
            Text(formatTime(viewModel.currentTime))
            Spacer()
            Text(formatTime(viewModel.duration))
          }
          .font(.system(size: 10, design: .monospaced))
          .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)

        HStack(spacing: 12) {
          Button(action: { viewModel.playPrevious() }) {
            Image(systemName: "backward.fill")
              .font(.system(size: 22))
              .foregroundColor(.white)
          }
          .buttonStyle(.plain)
          .disabled(viewModel.isLoading)
          Button(action: { viewModel.togglePlayPause() }) {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 34))
              .foregroundColor(.white)
          }
          .buttonStyle(.plain)
          Button(action: { viewModel.playNext() }) {
            Image(systemName: "forward.fill")
              .font(.system(size: 22))
              .foregroundColor(.white)
          }
          .buttonStyle(.plain)
          .disabled(viewModel.isLoading)
        }
        .padding(.bottom, 4)
      }
    }
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
