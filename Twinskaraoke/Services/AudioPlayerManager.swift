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
  @Published var currentSong: Song?
  @Published var isPlaying = false
  @Published var isBuffering = false
  @Published var progress: Double = 0.0
  @Published var queue: [Song] = []
  @Published var showFullScreen = false
  @Published var isEditingProgress = false
  @Published var volume: Double = 1.0
  @Published var isUserScrubbingVolume: Bool = false
  @Published var routeIcon: String = "airplayaudio"
  @Published var routeName: String = ""
  @Published var repeatMode: RepeatMode = .off
  @Published var isShuffled: Bool = false
  @Published var autoplayEnabled: Bool = true
  @Published var isRadioMode: Bool = false
  @Published var radioArtworkURL: URL?
  @Published var karaokeMode: Bool = false {
    didSet { KaraokeAudioProcessor.vocalAttenuation = karaokeMode ? karaokeStrength : 0 }
  }
  @Published var karaokeStrength: Float = 0.85 {
    didSet { if karaokeMode { KaraokeAudioProcessor.vocalAttenuation = karaokeStrength } }
  }
  @Published var autoMixEnabled: Bool =
    (UserDefaults.standard.object(forKey: "nk.autoMixEnabled") as? Bool ?? true)
  {
    didSet {
      UserDefaults.standard.set(autoMixEnabled, forKey: "nk.autoMixEnabled")
      scheduleAutoMixIfNeeded()
    }
  }
  @Published var crossfadeEnabled: Bool =
    (UserDefaults.standard.object(forKey: "nk.crossfadeEnabled") as? Bool ?? false)
  {
    didSet {
      UserDefaults.standard.set(crossfadeEnabled, forKey: "nk.crossfadeEnabled")
      scheduleAutoMixIfNeeded()
    }
  }
  @Published var crossfadeSeconds: Double = AudioPlayerManager.loadCrossfadeSeconds() {
    didSet {
      let clamped = min(15, max(1, crossfadeSeconds))
      if clamped != crossfadeSeconds {
        crossfadeSeconds = clamped
        return
      }
      UserDefaults.standard.set(crossfadeSeconds, forKey: "nk.crossfadeSeconds")
      scheduleAutoMixIfNeeded()
    }
  }
  @Published var upcomingSong: Song?
  #if canImport(UIKit)
    @Published var nowPlayingArtwork: UIImage?
  #endif
  private var crossfadePlayer: AVPlayer?
  private var crossfadeTimer: Timer?
  private var crossfadeRampTimer: Timer?
  private var crossfadeFallback: DispatchWorkItem?
  private var preloadedNext: (id: String, url: URL)?
  private var isCrossfading: Bool = false
  private static let crossfadeDuration: Double = 6.0
  private static func loadCrossfadeSeconds() -> Double {
    let raw = UserDefaults.standard.object(forKey: "nk.crossfadeSeconds") as? Double ?? 6.0
    return min(15, max(1, raw))
  }
  private var activeCrossfadeDuration: Double {
    if crossfadeEnabled { return min(15, max(1, crossfadeSeconds)) }
    if autoMixEnabled { return 2.5 }  // Auto Mix default blend.
    return 0
  }
  private var originalQueue: [Song] = []
  private var player: AVPlayer?
  private var timeObserver: (player: AVPlayer, token: Any)?
  private var cancellables = Set<AnyCancellable>()
  private var itemObservers = Set<AnyCancellable>()
  private var artworkURL: URL?
  private var artworkTask: URLSessionDataTask?
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
  #if canImport(UIKit)
    private static let artworkCache: NSCache<NSURL, UIImage> = {
      let cache = NSCache<NSURL, UIImage>()
      cache.countLimit = 32
      cache.totalCostLimit = 32 * 1024 * 1024
      return cache
    }()
    private static let artworkMaxPixel: CGFloat = 600
  #endif
  init() {
    configureAudioSessionCategory()
    activateAudioSession()
    #if os(iOS)
      UIApplication.shared.beginReceivingRemoteControlEvents()
    #endif
    setupRemoteCommands()
    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
      .sink { [weak self] _ in
        guard let self, !self.isCrossfading else { return }
        self.playNextOrRandom()
      }
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
        guard !self.isUserScrubbingVolume else { return }
        let v = Double(sysVol)
        if abs(self.volume - v) > 0.01 { self.volume = v }
      }
      .store(in: &cancellables)
    #if canImport(UIKit)
      NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
        .sink { [weak self] _ in self?.handleBackgroundTransition() }
        .store(in: &cancellables)
      NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
        .sink { _ in AudioPlayerManager.artworkCache.removeAllObjects() }
        .store(in: &cancellables)
    #endif
  }
  deinit {
    if let existing = timeObserver {
      existing.player.removeTimeObserver(existing.token)
    }
    crossfadeTimer?.invalidate()
    crossfadeRampTimer?.invalidate()
    crossfadeFallback?.cancel()
    artworkTask?.cancel()
    downloadSession?.cancel()
    player?.pause()
    crossfadePlayer?.pause()
  }
  func play(song: Song, context: [Song] = []) {
    if isRadioMode {
      RadioController.shared.stop()
    }
    isRadioMode = false
    radioArtworkURL = nil
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
    let downloadedURL = DownloadManager.shared.localURL(for: song.id)
    if FileManager.default.fileExists(atPath: downloadedURL.path) {
      startPlaying(url: downloadedURL)
      return
    }
    if FileManager.default.fileExists(atPath: cacheURL.path) {
      startPlaying(url: cacheURL)
      return
    }
    guard let remoteURL = song.audioURL else { return }
    isBuffering = true
    startPlaying(url: remoteURL)
    let session = AudioDownloadSession(songID: song.id)
    downloadSession = session
    session.start(from: remoteURL)
  }
  private func startPlaying(url: URL) {
    itemObservers.removeAll()
    cancelAutoMix()
    player?.currentItem?.audioMix = nil
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
    KaraokeAudioProcessor.attachVocalCancel(to: playerItem)
    NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
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
    scheduleAutoMixIfNeeded()
  }
  private func cancelAutoMix() {
    crossfadeTimer?.invalidate()
    crossfadeTimer = nil
    crossfadeRampTimer?.invalidate()
    crossfadeRampTimer = nil
    crossfadeFallback?.cancel()
    crossfadeFallback = nil
    crossfadePlayer?.currentItem?.audioMix = nil
    crossfadePlayer?.pause()
    crossfadePlayer = nil
    preloadedNext = nil
    upcomingSong = nil
    isCrossfading = false
  }
  private func scheduleAutoMixIfNeeded() {
    crossfadeTimer?.invalidate()
    crossfadeTimer = nil
    crossfadeRampTimer?.invalidate()
    crossfadeRampTimer = nil
    crossfadeFallback?.cancel()
    crossfadeFallback = nil
    crossfadePlayer?.pause()
    crossfadePlayer = nil
    preloadedNext = nil
    upcomingSong = nil
    guard !isRadioMode, let song = currentSong else { return }
    guard autoMixEnabled || crossfadeEnabled else { return }
    let duration = activeCrossfadeDuration
    let metaTotal = Double(song.duration)
    guard metaTotal > max(duration, 0.5) + 4 else { return }
    guard let next = nextQueuedSong(after: song) else { return }
    guard let nextURL = preferredURL(for: next) else { return }
    upcomingSong = next
    preloadNext(song: next, url: nextURL)
    crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
      [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      guard let item = self.player?.currentItem else { return }
      let elapsed = item.currentTime().seconds
      var actualTotal = item.duration.seconds
      if !actualTotal.isFinite || actualTotal <= 0 { actualTotal = metaTotal }
      guard elapsed.isFinite, actualTotal.isFinite, actualTotal > 0 else { return }
      let triggerAt = actualTotal - max(duration, 1.0)
      if elapsed >= triggerAt {
        timer.invalidate()
        self.crossfadeTimer = nil
        self.beginCrossfade(to: next)
      }
    }
  }
  private func preloadNext(song: Song, url: URL) {
    let item = AVPlayerItem(url: url)
    KaraokeAudioProcessor.attachVocalCancel(to: item)
    let standby = AVPlayer(playerItem: item)
    if #available(iOS 15.0, *) {
      standby.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }
    standby.automaticallyWaitsToMinimizeStalling = false
    standby.volume = 0
    crossfadePlayer = standby
    preloadedNext = (song.id, url)
    var statusObserver: AnyCancellable?
    statusObserver = item.publisher(for: \.status)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        guard let self else {
          statusObserver?.cancel()
          return
        }
        guard self.crossfadePlayer === standby else {
          statusObserver?.cancel()
          return
        }
        switch status {
        case .readyToPlay:
          statusObserver?.cancel()
          standby.preroll(atRate: 1.0) { _ in }
        case .failed:
          statusObserver?.cancel()
        default:
          break
        }
      }
    statusObserver?.store(in: &itemObservers)
  }
  private func nextQueuedSong(after song: Song) -> Song? {
    guard !queue.isEmpty,
      let idx = queue.firstIndex(of: song),
      idx + 1 < queue.count
    else { return nil }
    return queue[idx + 1]
  }
  private func preferredURL(for song: Song) -> URL? {
    let downloaded = DownloadManager.shared.localURL(for: song.id)
    if FileManager.default.fileExists(atPath: downloaded.path) { return downloaded }
    let cached = AudioPlayerManager.audioCacheDir.appendingPathComponent("\(song.id).mp3")
    if FileManager.default.fileExists(atPath: cached.path) { return cached }
    return song.audioURL
  }
  private func beginCrossfade(to next: Song) {
    guard let nextPlayer = crossfadePlayer else { return }
    nextPlayer.volume = 0
    var crossfadeStarted = false
    let runRamp: () -> Void = { [weak self] in
      guard let self, self.crossfadePlayer === nextPlayer else { return }
      self.isCrossfading = true
      let duration = self.activeCrossfadeDuration
      if duration < 0.05 {
        self.player?.pause()
        self.player?.volume = 1.0
        nextPlayer.volume = 1.0
        self.crossfadeRampTimer?.invalidate()
        self.crossfadeRampTimer = nil
        self.crossfadePlayer = nil
        self.preloadedNext = nil
        self.handoffToCrossfaded(player: nextPlayer, song: next)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          self?.isCrossfading = false
        }
        return
      }
      let steps = 60
      let interval = duration / Double(steps)
      var step = 0
      self.crossfadeRampTimer?.invalidate()
      let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
        [weak self] timer in
        guard let self, self.crossfadePlayer === nextPlayer else {
          timer.invalidate()
          return
        }
        step += 1
        let t = Float(step) / Float(steps)
        let angle = t * Float.pi / 2
        self.player?.volume = cos(angle)
        nextPlayer.volume = sin(angle)
        if step >= steps {
          timer.invalidate()
          self.crossfadeRampTimer = nil
          self.player?.pause()
          self.player?.volume = 1.0
          nextPlayer.volume = 1.0
          self.crossfadePlayer = nil
          self.preloadedNext = nil
          self.handoffToCrossfaded(player: nextPlayer, song: next)
          self.isCrossfading = false
        }
      }
      self.crossfadeRampTimer = timer
    }
    let startCrossfade: () -> Void = { [weak self] in
      guard let self, !crossfadeStarted, self.crossfadePlayer === nextPlayer else { return }
      crossfadeStarted = true
      self.crossfadeFallback?.cancel()
      self.crossfadeFallback = nil
      nextPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        guard let self, self.crossfadePlayer === nextPlayer else { return }
        nextPlayer.play()
        var rampStarted = false
        var statusObserver: AnyCancellable?
        statusObserver = nextPlayer.publisher(for: \.timeControlStatus)
          .receive(on: DispatchQueue.main)
          .sink { state in
            guard !rampStarted, state == .playing else { return }
            rampStarted = true
            statusObserver?.cancel()
            runRamp()
          }
        statusObserver?.store(in: &self.itemObservers)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
          guard !rampStarted, self.crossfadePlayer === nextPlayer else { return }
          rampStarted = true
          statusObserver?.cancel()
          runRamp()
        }
      }
    }
    if let item = nextPlayer.currentItem, item.status == .readyToPlay {
      startCrossfade()
      return
    }
    var observer: AnyCancellable?
    observer = nextPlayer.currentItem?.publisher(for: \.status)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        if status == .readyToPlay {
          observer?.cancel()
          startCrossfade()
        } else if status == .failed {
          observer?.cancel()
          guard let self else { return }
          if self.crossfadePlayer === nextPlayer {
            nextPlayer.pause()
            self.crossfadePlayer = nil
            self.preloadedNext = nil
          }
        }
      }
    observer?.store(in: &itemObservers)
    let fallback = DispatchWorkItem { [weak self] in
      guard let self, !crossfadeStarted, self.crossfadePlayer === nextPlayer else { return }
      observer?.cancel()
      nextPlayer.pause()
      self.crossfadePlayer = nil
      self.preloadedNext = nil
    }
    crossfadeFallback = fallback
    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: fallback)
  }
  private func handoffToCrossfaded(player nextPlayer: AVPlayer, song: Song) {
    itemObservers.removeAll()
    player = nextPlayer
    setupTimeObserver()
    if isShuffled {
    }
    progress = 0
    withAnimation(.easeInOut(duration: 0.32)) {
      currentSong = song
    }
    isPlaying = true
    if let item = nextPlayer.currentItem {
      item.publisher(for: \.isPlaybackBufferEmpty)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] empty in
          if empty { self?.isBuffering = true }
        }
        .store(in: &itemObservers)
      item.publisher(for: \.isPlaybackLikelyToKeepUp)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] likely in
          if likely { self?.isBuffering = false }
        }
        .store(in: &itemObservers)
    }
    updateNowPlayingInfo(reloadArtwork: true)
    scheduleAutoMixIfNeeded()
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
      NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
      player?.play()
    }
    isPlaying.toggle()
    updateNowPlayingInfo(reloadArtwork: false)
  }
  func playRadio(streamURL: URL, song: Song, artworkURL: URL?) {
    let alreadyOnSameStation = isRadioMode && currentSong?.id == song.id
    if alreadyOnSameStation {
      currentSong = song
      radioArtworkURL = artworkURL
      updateNowPlayingInfo(reloadArtwork: true)
      return
    }
    downloadSession?.cancel()
    isRadioMode = true
    radioArtworkURL = artworkURL
    progress = 0
    queue = []
    originalQueue = []
    withAnimation(.easeInOut(duration: 0.32)) {
      currentSong = song
    }
    isBuffering = true
    startPlaying(url: streamURL)
  }
  func updateRadioMetadata(song: Song, artworkURL: URL?) {
    guard isRadioMode else { return }
    currentSong = song
    radioArtworkURL = artworkURL
    updateNowPlayingInfo(reloadArtwork: true)
  }
  func pauseIfPlaying() {
    if isPlaying {
      player?.pause()
      isPlaying = false
      updateNowPlayingInfo(reloadArtwork: false)
    }
  }
  func displayImageURL(for song: Song) -> URL? {
    if isRadioMode, currentSong?.id == song.id, let art = radioArtworkURL {
      return art
    }
    return song.imageURL
  }
  func playNextOrRandom() {
    if isRadioMode { return }
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
    if isRadioMode { return }
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
  func seek(to fraction: Double) {
    guard fraction.isFinite, (0.0...1.0).contains(fraction) else { return }
    guard let duration = player?.currentItem?.duration.seconds,
      duration.isFinite, duration > 0
    else { return }
    let target = duration * fraction
    guard target.isFinite else { return }
    player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    updateNowPlayingInfo(reloadArtwork: false)
  }
  private func setupTimeObserver() {
    if let existing = timeObserver {
      existing.player.removeTimeObserver(existing.token)
      timeObserver = nil
    }
    guard let player else { return }
    let token = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
    ) { [weak self] time in
      guard let self = self, !self.isEditingProgress,
        let duration = self.player?.currentItem?.duration.seconds,
        duration.isFinite, duration > 0
      else { return }
      self.progress = time.seconds / duration
      self.updateNowPlayingElapsed(time.seconds)
    }
    timeObserver = (player, token)
  }
  private func configureAudioSessionCategory() {
    do {
      if #available(iOS 13.0, *) {
        try AVAudioSession.sharedInstance().setCategory(
          .playback, mode: .default, policy: .longFormAudio, options: [])
      } else {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
      }
    } catch {}
  }
  private func activateAudioSession() {
    try? AVAudioSession.sharedInstance().setActive(true, options: [])
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
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
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
    if isRadioMode {
      info[MPNowPlayingInfoPropertyIsLiveStream] = true
      info[MPMediaItemPropertyPlaybackDuration] = nil
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nil
    } else {
      info[MPNowPlayingInfoPropertyIsLiveStream] = false
      info[MPMediaItemPropertyPlaybackDuration] = Double(song.duration)
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress * Double(song.duration)
    }
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    let targetArt = isRadioMode ? radioArtworkURL : song.imageURL
    if reloadArtwork || artworkURL != targetArt {
      info[MPMediaItemPropertyArtwork] = nil
      artworkURL = targetArt
      #if canImport(UIKit)
        if reloadArtwork { nowPlayingArtwork = nil }
      #endif
      if let targetArt {
        loadArtworkAsync(from: targetArt)
      }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  private func updateNowPlayingElapsed(_ elapsed: Double) {
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  private func loadArtworkAsync(from url: URL) {
    let songID = currentSong?.id
    artworkTask?.cancel()
    artworkTask = nil
    #if canImport(UIKit)
      if let cached = AudioPlayerManager.artworkCache.object(forKey: url as NSURL) {
        applyArtwork(cached, for: songID)
        return
      }
    #endif
    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let self = self, let data = data,
        self.currentSong?.id == songID
      else { return }
      #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return }
        let squareImage = image.croppedToSquare().downscaled(
          maxPixel: AudioPlayerManager.artworkMaxPixel)
        let cost = Int(squareImage.size.width * squareImage.size.height * squareImage.scale
          * squareImage.scale * 4)
        AudioPlayerManager.artworkCache.setObject(squareImage, forKey: url as NSURL, cost: cost)
        self.applyArtwork(squareImage, for: songID)
      #endif
    }
    artworkTask = task
    task.resume()
  }
  #if canImport(UIKit)
    private func applyArtwork(_ image: UIImage, for songID: String?) {
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.currentSong?.id == songID else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        self.nowPlayingArtwork = image
      }
    }
  #endif
  private func fetchRandomTrending() {
    guard let url = URL(string: "https://api.neurokaraoke.com/api/explore/trendings?days=7&take=50")
    else { return }
    var request = URLRequest(url: url)
    request.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { data, _, _ in
      if let data = data, let songs = try? JSONDecoder().decode([Song].self, from: data),
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
    func downscaled(maxPixel: CGFloat) -> UIImage {
      let pixelW = size.width * scale
      let pixelH = size.height * scale
      let longest = max(pixelW, pixelH)
      guard longest > maxPixel else { return self }
      let ratio = maxPixel / longest
      let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
      return renderer.image { _ in
        draw(in: CGRect(origin: .zero, size: newSize))
      }
    }
  }
#endif
