//
//  AudioPlayerManager.swift
//  Twinskaraoke
//
//  Created by xiaoyuan on 2026/4/26.
//
import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

enum RepeatMode {
  case off, all, one
  var symbol: String {
    switch self {
    case .off, .all: return "repeat"
    case .one: return "repeat.1"
    }
  }
  var isActive: Bool { self != .off }
  func next() -> RepeatMode {
    switch self {
    case .off: return .all
    case .all: return .one
    case .one: return .off
    }
  }
}

private final class AudioDownloadSession: NSObject, URLSessionDataDelegate {
  private let songID: String
  private let cacheURL: URL
  private var fileHandle: FileHandle?
  private var task: URLSessionDataTask?
  private var session: URLSession?

  init(songID: String) {
    self.songID = songID
    self.cacheURL = AudioPlayerManager.audioCacheDir.appendingPathComponent("\(songID).mp3")
    super.init()
  }

  func start(from remoteURL: URL) {
    FileManager.default.createFile(atPath: cacheURL.path, contents: nil)
    self.fileHandle = try? FileHandle(forWritingTo: cacheURL)
    session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    task = session?.dataTask(with: remoteURL)
    task?.resume()
  }

  func cancel() {
    task?.cancel()
    session?.invalidateAndCancel()
    fileHandle?.closeFile()
    try? FileManager.default.removeItem(at: cacheURL)
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    fileHandle?.write(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    fileHandle?.closeFile()
    session.invalidateAndCancel()
    if error != nil {
      try? FileManager.default.removeItem(at: cacheURL)
    }
  }
}

class AudioPlayerManager: ObservableObject {
  static let shared = AudioPlayerManager()
  @Published var currentSong: PhoneSong?
  @Published var isPlaying = false
  @Published var isBuffering = false
  @Published var progress: Double = 0.0
  @Published var queue: [PhoneSong] = []
  @Published var showFullScreen = false
  @Published var isEditingProgress = false
  @Published var volume: Double = 1.0
  @Published var routeIcon: String = "airplayaudio"
  @Published var routeName: String = ""
  @Published var repeatMode: RepeatMode = .off
  @Published var isShuffled: Bool = false
  @Published var autoplayEnabled: Bool = true
  private var originalQueue: [PhoneSong] = []
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var itemObservers = Set<AnyCancellable>()
  private var artworkURL: URL?
  private var downloadSession: AudioDownloadSession?
  #if canImport(UIKit)
  private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
  #endif

  static let audioCacheDir: URL = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("AudioCache")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  init() {
    configureAudioSessionCategory()
    activateAudioSession()
    #if os(iOS)
    UIApplication.shared.beginReceivingRemoteControlEvents()
    #endif
    setupRemoteCommands()
    logBackgroundAudioDiagnostics()
    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
      .sink { [weak self] _ in self?.playNextOrRandom() }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .sink { [weak self] note in self?.handleInterruption(note) }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
      .sink { [weak self] note in self?.handleRouteChange(note) }
      .store(in: &cancellables)
    updateRouteIcon()
    AVAudioSession.sharedInstance().publisher(for: \.outputVolume)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] sysVol in
        guard let self = self else { return }
        let v = Double(sysVol)
        if abs(self.volume - v) > 0.01 { self.volume = v }
      }
      .store(in: &cancellables)
    #if canImport(UIKit)
    NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
      .sink { [weak self] _ in self?.handleBackgroundTransition() }
      .store(in: &cancellables)
    #endif
  }

  func play(song: PhoneSong, context: [PhoneSong] = []) {
    if currentSong?.id != song.id {
      progress = 0
      withAnimation(.easeInOut(duration: 0.32)) {
        currentSong = song
      }
    } else {
      currentSong = song
    }
    if !context.isEmpty {
      queue = context
      if isShuffled {
        originalQueue = context
        var rest = queue.filter { $0.id != song.id }
        rest.shuffle()
        queue = [song] + rest
      } else {
        originalQueue = []
      }
    }
    downloadSession?.cancel()

    let cacheURL = AudioPlayerManager.audioCacheDir.appendingPathComponent("\(song.id).mp3")
    if FileManager.default.fileExists(atPath: cacheURL.path) {
      startPlaying(url: cacheURL)
      return
    }

    guard let remoteURL = song.audioURL else { return }
    // Stream from remote URL — AVPlayer handles HTTP streaming and background
    // playback natively. The download below populates the cache for next time.
    isBuffering = true
    startPlaying(url: remoteURL)

    let session = AudioDownloadSession(songID: song.id)
    downloadSession = session
    session.start(from: remoteURL)
  }

  private func startPlaying(url: URL) {
    itemObservers.removeAll()
    let playerItem = AVPlayerItem(url: url)
    if player == nil {
      player = AVPlayer(playerItem: playerItem)
      if #available(iOS 15.0, *) {
        player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
      }
      player?.automaticallyWaitsToMinimizeStalling = true
      player?.allowsExternalPlayback = true
      player?.volume = 1.0
      setupTimeObserver()
    } else {
      player?.replaceCurrentItem(with: playerItem)
      player?.volume = 1.0
    }
    player?.play()
    isPlaying = true

    playerItem.publisher(for: \.isPlaybackBufferEmpty)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] empty in
        if empty { self?.isBuffering = true }
      }
      .store(in: &itemObservers)
    playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] likely in
        if likely { self?.isBuffering = false }
      }
      .store(in: &itemObservers)

    updateNowPlayingInfo(reloadArtwork: true)
  }

  #if canImport(UIKit)
  private func handleBackgroundTransition() {
    if bgTaskID != .invalid {
      UIApplication.shared.endBackgroundTask(bgTaskID)
    }
    bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "AudioCache") { [weak self] in
      guard let self = self else { return }
      if self.bgTaskID != .invalid {
        UIApplication.shared.endBackgroundTask(self.bgTaskID)
        self.bgTaskID = .invalid
      }
    }
  }
  #endif
  func togglePlayPause() {
    if isPlaying {
      player?.pause()
    } else {
      player?.play()
    }
    isPlaying.toggle()
    updateNowPlayingInfo(reloadArtwork: false)
  }
  func playNextOrRandom() {
    if repeatMode == .one, let current = currentSong {
      play(song: current)
      return
    }
    if let current = currentSong, !queue.isEmpty, let idx = queue.firstIndex(of: current),
      idx + 1 < queue.count
    {
      play(song: queue[idx + 1])
    } else if repeatMode == .all, let first = queue.first {
      play(song: first)
    } else if autoplayEnabled {
      fetchRandomTrending()
    } else {
      isPlaying = false
      player?.pause()
      updateNowPlayingInfo(reloadArtwork: false)
    }
  }
  func playPrevious() {
    if let current = currentSong, !queue.isEmpty, let idx = queue.firstIndex(of: current),
      idx - 1 >= 0
    {
      play(song: queue[idx - 1])
    } else {
      seek(to: 0)
    }
  }
  func toggleRepeat() {
    repeatMode = repeatMode.next()
  }
  func toggleShuffle() {
    isShuffled.toggle()
    if isShuffled {
      originalQueue = queue
      guard let current = currentSong else { return }
      var rest = queue.filter { $0.id != current.id }
      rest.shuffle()
      queue = [current] + rest
    } else if !originalQueue.isEmpty {
      queue = originalQueue
      originalQueue = []
    }
  }
  func toggleAutoplay() {
    autoplayEnabled.toggle()
  }
  func moveInUpNext(from source: IndexSet, to destination: Int) {
    guard let current = currentSong,
      let baseIdx = queue.firstIndex(of: current)
    else { return }
    let upNextStart = baseIdx + 1
    guard upNextStart < queue.count else { return }
    var upNext = Array(queue[upNextStart...])
    upNext.move(fromOffsets: source, toOffset: destination)
    queue = Array(queue[..<upNextStart]) + upNext
  }
  func removeFromUpNext(at offsets: IndexSet) {
    guard let current = currentSong,
      let baseIdx = queue.firstIndex(of: current)
    else { return }
    let upNextStart = baseIdx + 1
    guard upNextStart < queue.count else { return }
    var upNext = Array(queue[upNextStart...])
    upNext.remove(atOffsets: offsets)
    queue = Array(queue[..<upNextStart]) + upNext
  }
  func seek(to percentage: Double) {
    guard let duration = player?.currentItem?.duration.seconds, duration.isFinite else { return }
    player?.seek(to: CMTime(seconds: duration * percentage, preferredTimescale: 600))
    updateNowPlayingInfo(reloadArtwork: false)
  }
  private func setupTimeObserver() {
    timeObserver = player?.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
    ) { [weak self] time in
      guard let self = self, !self.isEditingProgress,
        let duration = self.player?.currentItem?.duration.seconds,
        duration.isFinite, duration > 0
      else { return }
      self.progress = time.seconds / duration
      self.updateNowPlayingElapsed(time.seconds)
    }
  }
  private func configureAudioSessionCategory() {
    do {
      if #available(iOS 13.0, *) {
        try AVAudioSession.sharedInstance().setCategory(
          .playback, mode: .default, policy: .longFormAudio, options: [])
      } else {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
      }
    } catch {
      print("Audio session category setup failed: \(error)")
    }
  }
  private func activateAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setActive(true, options: [])
    } catch {
      print("Audio session activation failed: \(error)")
    }
  }
  private func logBackgroundAudioDiagnostics() {
    let bg = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    let session = AVAudioSession.sharedInstance()
    print("=== Background Audio Diagnostics ===")
    print("Info.plist UIBackgroundModes: \(bg)")
    print("  audio enabled: \(bg.contains("audio"))")
    print("Audio session category: \(session.category.rawValue)")
    print("Audio session mode: \(session.mode.rawValue)")
    print("Audio session policy: \(session.routeSharingPolicy.rawValue)")
    print("Audio session is other audio playing: \(session.isOtherAudioPlaying)")
    print("Output route: \(session.currentRoute.outputs.map(\.portName))")
    print("====================================")
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
        updateNowPlayingInfo(reloadArtwork: false)
      }
    case .ended:
      guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
      let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
      if opts.contains(.shouldResume) {
        activateAudioSession()
        player?.play()
        isPlaying = true
        updateNowPlayingInfo(reloadArtwork: false)
      }
    @unknown default: break
    }
  }
  private func handleRouteChange(_ note: Notification) {
    updateRouteIcon()
    guard let info = note.userInfo,
      let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
    else { return }
    if reason == .oldDeviceUnavailable, isPlaying {
      player?.pause()
      isPlaying = false
      updateNowPlayingInfo(reloadArtwork: false)
    }
  }
  func updateRouteIcon() {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    guard let primary = outputs.first else {
      routeIcon = "airplayaudio"
      routeName = ""
      return
    }
    routeName = primary.portName
    let nameLower = primary.portName.lowercased()
    switch primary.portType {
    case .builtInSpeaker, .builtInReceiver:
      routeIcon = "airplayaudio"
    case .headphones:
      routeIcon = "headphones"
    case .HDMI:
      routeIcon = "tv.fill"
    case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
      if nameLower.contains("airpods max") {
        routeIcon = "airpodsmax"
      } else if nameLower.contains("airpods pro") {
        routeIcon = "airpodspro"
      } else if nameLower.contains("airpods") {
        routeIcon = "airpods"
      } else if nameLower.contains("beats") {
        routeIcon = "beats.headphones"
      } else {
        routeIcon = "hifispeaker.fill"
      }
    case .airPlay:
      if nameLower.contains("homepod mini") {
        routeIcon = "homepodmini"
      } else if nameLower.contains("homepod") {
        routeIcon = "homepod"
      } else if nameLower.contains("apple tv") {
        routeIcon = "appletv"
      } else {
        routeIcon = "airplayaudio"
      }
    default:
      routeIcon = "airplayaudio"
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
      self?.playNextOrRandom()
      return .success
    }
    cc.previousTrackCommand.addTarget { [weak self] _ in
      self?.playPrevious()
      return .success
    }
    cc.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self = self,
        let positionEvent = event as? MPChangePlaybackPositionCommandEvent,
        let duration = self.player?.currentItem?.duration.seconds,
        duration.isFinite, duration > 0
      else { return .commandFailed }
      self.seek(to: positionEvent.positionTime / duration)
      return .success
    }
  }
  private func updateNowPlayingInfo(reloadArtwork: Bool) {
    guard let song = currentSong else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = song.title
    info[MPMediaItemPropertyArtist] = song.originalArtists?.joined(separator: ", ") ?? ""
    info[MPMediaItemPropertyPlaybackDuration] = Double(song.duration)
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress * Double(song.duration)
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    if reloadArtwork || artworkURL != song.imageURL {
      info[MPMediaItemPropertyArtwork] = nil
      artworkURL = song.imageURL
      loadArtworkAsync(for: song)
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  private func updateNowPlayingElapsed(_ elapsed: Double) {
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  private func loadArtworkAsync(for song: PhoneSong) {
    guard let url = song.imageURL else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let self = self, let data = data,
        self.currentSong?.id == song.id
      else { return }
      #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return }
        let squareImage = image.croppedToSquare()
        let artwork = MPMediaItemArtwork(boundsSize: squareImage.size) { _ in squareImage }
        DispatchQueue.main.async {
          var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
          info[MPMediaItemPropertyArtwork] = artwork
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
      #endif
    }.resume()
  }
  private func fetchRandomTrending() {
    guard let url = URL(string: "https://api.neurokaraoke.com/api/explore/trendings?days=7&take=50")
    else { return }
    var request = URLRequest(url: url)
    request.setValue("75f57152-9f21-44a5-8c65-e74cc5710cb8", forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { data, _, _ in
      if let data = data, let songs = try? JSONDecoder().decode([PhoneSong].self, from: data),
        let random = songs.randomElement()
      {
        DispatchQueue.main.async { self.play(song: random, context: songs) }
      }
    }.resume()
  }
}

#if canImport(UIKit)
extension UIImage {
  func croppedToSquare() -> UIImage {
    let originalWidth = size.width
    let originalHeight = size.height
    let sideLength = min(originalWidth, originalHeight)
    let xOffset = (originalWidth - sideLength) / 2.0
    let yOffset = (originalHeight - sideLength) / 2.0
    let cropRect = CGRect(x: xOffset, y: yOffset, width: sideLength, height: sideLength)
    guard let cgImage = cgImage?.cropping(to: cropRect) else { return self }
    return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
  }
}
#endif
