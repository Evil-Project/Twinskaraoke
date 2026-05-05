import AVFoundation
import Combine
import Foundation
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

@MainActor
class AudioManager: ObservableObject {
  static let shared = AudioManager()
  @Published var currentSong: Song?
  @Published var isPlaying = false
  @Published var isLoading = false
  @Published var currentTime: Double = 0
  @Published var duration: Double = 0
  @Published var queue: [Song] = []
  @Published var currentIndex: Int = 0
  @Published var playbackMode: PlaybackMode = .listLoop
  @Published var isShuffleOn = false
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endTimeObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var downloadTask: URLSessionDownloadTask?
  private static let audioCacheDir: URL = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("AudioCache")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()
  private static let maxCachedFiles = 10
  init() {
    setupRemoteCommands()
    setupInterruptionHandler()
  }
  var progress: Double {
    guard duration > 0 else { return 0 }
    return currentTime / duration
  }
  func play(song: Song, context: [Song] = []) {
    currentSong = song
    if !context.isEmpty {
      queue = context
      if let idx = context.firstIndex(of: song) {
        currentIndex = idx
      }
    }
    prepareAndPlay()
  }
  private func prepareAndPlay() {
    cleanupPlayer()
    currentTime = 0
    duration = 0
    isPlaying = false
    cancellables.removeAll()
    setupInterruptionHandler()
    downloadTask?.cancel()
    guard let song = currentSong else { return }
    let localURL = localCacheURL(for: song.id)
    if FileManager.default.fileExists(atPath: localURL.path) {
      setupPlayer(with: localURL)
      return
    }
    guard let remoteURL = song.audioURL else { return }
    isLoading = true
    downloadTask = URLSession.shared.downloadTask(with: remoteURL) {
      [weak self] tempURL, _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.isLoading = false
        guard let tempURL = tempURL, error == nil else { return }
        try? FileManager.default.moveItem(at: tempURL, to: localURL)
        guard self.currentSong?.id == song.id else { return }
        self.evictOldCacheFiles()
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
    } catch {}
    let playerItem = AVPlayerItem(url: localURL)
    self.player = AVPlayer(playerItem: playerItem)
    player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    playerItem.publisher(for: \.duration)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] dur in
        let seconds = CMTimeGetSeconds(dur)
        if !seconds.isNaN && seconds > 0 {
          self?.duration = seconds
        }
      }
      .store(in: &cancellables)
    playerItem.publisher(for: \.status)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        guard let self = self else { return }
        if status == .readyToPlay {
          self.isLoading = false
          self.player?.play()
          self.isPlaying = true
          self.updateNowPlayingInfo()
        } else if status == .failed {
          self.isLoading = false
          self.playNext()
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
  func togglePlayPause() {
    if isPlaying {
      player?.pause()
    } else {
      do {
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {}
      player?.play()
    }
    isPlaying.toggle()
    updateNowPlayingInfo()
  }
  func playNext() {
    guard !queue.isEmpty else { return }
    if isShuffleOn && queue.count > 1 {
      var nextIndex = currentIndex
      while nextIndex == currentIndex {
        nextIndex = Int.random(in: 0..<queue.count)
      }
      currentIndex = nextIndex
    } else {
      currentIndex = (currentIndex + 1) % queue.count
    }
    currentSong = queue[currentIndex]
    prepareAndPlay()
  }
  func playPrevious() {
    if currentTime > 3.0 {
      player?.seek(to: .zero)
    } else if currentIndex > 0 {
      currentIndex -= 1
      currentSong = queue[currentIndex]
      prepareAndPlay()
    } else {
      player?.seek(to: .zero)
    }
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
  func seek(to time: Double) {
    player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    updateNowPlayingInfo()
  }
  private func cleanupPlayer() {
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }
    if let observer = endTimeObserver {
      NotificationCenter.default.removeObserver(observer)
      endTimeObserver = nil
    }
    player?.pause()
    player = nil
  }
  private func localCacheURL(for songID: String) -> URL {
    AudioManager.audioCacheDir.appendingPathComponent("\(songID).mp3")
  }
  private func evictOldCacheFiles() {
    let fm = FileManager.default
    let dir = AudioManager.audioCacheDir
    guard
      let files = try? fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return }
    guard files.count > AudioManager.maxCachedFiles else { return }
    let sorted = files.sorted {
      let d1 =
        (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        ?? .distantPast
      let d2 =
        (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        ?? .distantPast
      return d1 < d2
    }
    let toRemove = sorted.prefix(files.count - AudioManager.maxCachedFiles)
    for file in toRemove {
      try? fm.removeItem(at: file)
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
        do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
      }
    @unknown default: break
    }
  }
  private func updateNowPlayingInfo() {
    guard let song = currentSong else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = song.title
    info[MPMediaItemPropertyArtist] = song.artistName
    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
