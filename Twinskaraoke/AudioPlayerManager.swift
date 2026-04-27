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
import UIKit

class AudioPlayerManager: ObservableObject {
  static let shared = AudioPlayerManager()
  @Published var currentSong: PhoneSong?
  @Published var isPlaying = false
  @Published var progress: Double = 0.0
  @Published var queue: [PhoneSong] = []
  @Published var showFullScreen = false
  @Published var isEditingProgress = false
  @Published var volume: Double = 1.0 {
    didSet { player?.volume = Float(max(0, min(1, volume))) }
  }
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var artworkURL: URL?
  init() {
    configureAudioSessionCategory()
    setupRemoteCommands()
    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
      .sink { [weak self] _ in self?.playNextOrRandom() }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .sink { [weak self] note in self?.handleInterruption(note) }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
      .sink { [weak self] note in self?.handleRouteChange(note) }
      .store(in: &cancellables)
  }
  func play(song: PhoneSong, context: [PhoneSong] = []) {
    currentSong = song
    if !context.isEmpty { queue = context }
    guard let url = song.audioURL else { return }
    activateAudioSession()
    let playerItem = AVPlayerItem(url: url)
    if player == nil {
      player = AVPlayer(playerItem: playerItem)
      player?.automaticallyWaitsToMinimizeStalling = true
      player?.volume = Float(volume)
      setupTimeObserver()
    } else {
      player?.replaceCurrentItem(with: playerItem)
    }
    player?.play()
    isPlaying = true
    updateNowPlayingInfo(reloadArtwork: true)
  }
  func togglePlayPause() {
    if isPlaying {
      player?.pause()
    } else {
      activateAudioSession()
      player?.play()
    }
    isPlaying.toggle()
    updateNowPlayingInfo(reloadArtwork: false)
  }
  func playNextOrRandom() {
    if let current = currentSong, !queue.isEmpty, let idx = queue.firstIndex(of: current),
      idx + 1 < queue.count
    {
      play(song: queue[idx + 1])
    } else {
      fetchRandomTrending()
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
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
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
  private func handleInterruption(_ note: Notification) {
    guard let info = note.userInfo,
      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }
    switch type {
    case .began:
      if isPlaying {
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
      guard let self = self, let data = data, let image = UIImage(data: data),
        self.currentSong?.id == song.id
      else { return }
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      }
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
