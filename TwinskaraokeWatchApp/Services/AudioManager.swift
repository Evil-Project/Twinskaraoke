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
        case .listLoop: "repeat"
        case .singleLoop: "repeat.1"
        }
    }
}

@MainActor
class AudioManager: ObservableObject {
    static let shared = AudioManager()
    @Published var currentSong: Song? {
        didSet { refreshUpNext() }
    }
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var queue: [Song] = [] {
        didSet { refreshUpNext() }
    }
    @Published var currentIndex: Int = 0 {
        didSet { refreshUpNext() }
    }
    /// Up-next slice of the queue plus its summary string, recomputed only when
    /// the queue or current track changes (views re-evaluate on every 0.5s tick).
    @Published private(set) var upNextSongs: [Song] = []
    @Published private(set) var queueSummaryText = "End of queue"
    @Published var playbackMode: PlaybackMode = .listLoop
    @Published var isShuffleOn = false
    @Published var volume: Double = AudioManager.storedVolume()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endTimeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var downloadTask: URLSessionDownloadTask?
    private var downloadToken: UUID?
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var recoveringFromBrokenCache: Set<String> = []
    private var volumePersistWorkItem: DispatchWorkItem?
    private var playbackRequested = false
    private var shouldResumeAfterInterruption = false
    private static let audioCacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let maxCachedFiles = 10
    private static let volumeDefaultsKey = "nk.watchVolume"
    init() {
        setupRemoteCommands()
        setupInterruptionHandler()
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private func refreshUpNext() {
        guard let index = resolvedCurrentQueueIndex else {
            upNextSongs = []
            queueSummaryText = "End of queue"
            return
        }
        let nextIndex = index + 1
        guard nextIndex < queue.endIndex else {
            upNextSongs = []
            queueSummaryText = "End of queue"
            return
        }
        let songs = Array(queue[nextIndex...])
        upNextSongs = songs
        let countText = songs.count == 1 ? "1 song next" : "\(songs.count) songs next"
        queueSummaryText = "\(countText) - \(Self.queueDurationText(for: songs))"
    }

    private static func queueDurationText(for songs: [Song]) -> String {
        let totalSeconds = songs.reduce(0) { $0 + max(0, $1.duration) }
        guard totalSeconds > 0 else { return "0:00" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    func play(song: Song, context: [Song] = []) {
        var playbackQueue = context.isEmpty ? [song] : context
        if let index = playbackQueue.firstIndex(of: song) {
            currentIndex = index
        } else {
            playbackQueue.insert(song, at: 0)
            currentIndex = 0
        }
        queue = playbackQueue
        currentSong = song
        prepareAndPlay()
    }

    private func prepareAndPlay() {
        cleanupPlayer()
        currentTime = 0
        duration = 0
        isPlaying = false
        playbackRequested = true
        cancellables.removeAll()
        setupInterruptionHandler()
        downloadTask?.cancel()
        downloadToken = nil
        guard let song = currentSong else {
            playbackRequested = false
            isLoading = false
            return
        }
        let localURL = localCacheURL(for: song.id)
        if FileManager.default.fileExists(atPath: localURL.path) {
            isLoading = true
            validateCacheAndPlay(song: song, cacheURL: localURL)
            return
        }
        guard let remoteURL = song.audioURL else {
            playbackRequested = false
            isLoading = false
            return
        }
        isLoading = true
        let token = UUID()
        downloadToken = token
        downloadTask = URLSession.shared.downloadTask(with: remoteURL) {
            [weak self] tempURL, response, error in
            let responseAccepted = Self.acceptsAudioResponse(response)
            DispatchQueue.main.async {
                guard let self,
                      self.downloadToken == token,
                      self.currentSong?.id == song.id
                else { return }
                self.downloadToken = nil
                self.downloadTask = nil
                self.isLoading = false
                guard let tempURL, error == nil else {
                    self.playbackRequested = false
                    return
                }
                self.finishDownloadedPlayback(
                    tempURL: tempURL,
                    responseAccepted: responseAccepted,
                    destinationURL: localURL,
                    song: song
                )
            }
        }
        downloadTask?.resume()
    }

    private func setupPlayer(with localURL: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, policy: .longFormAudio
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        let playerItem = AVPlayerItem(url: localURL)
        let player = AVPlayer(playerItem: playerItem)
        player.volume = Float(volume)
        self.player = player
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        playerItem.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                let seconds = CMTimeGetSeconds(dur)
                if !seconds.isNaN, seconds > 0 {
                    self?.duration = seconds
                }
            }
            .store(in: &cancellables)
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .readyToPlay {
                    if playbackRequested {
                        player.play()
                    }
                    refreshPlaybackState()
                    updateNowPlayingInfo()
                } else if status == .failed {
                    isLoading = false
                    isPlaying = false
                    if !recoverFromBrokenCache(playbackURL: localURL) {
                        playbackRequested = false
                        playNext()
                    }
                }
            }
            .store(in: &cancellables)
        player.publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPlaybackState()
            }
            .store(in: &cancellables)
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite, !seconds.isNaN {
                    currentTime = max(0, seconds)
                }
            }
        }
        if let oldObserver = endTimeObserver {
            NotificationCenter.default.removeObserver(oldObserver)
        }
        endTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playEnded()
            }
        }
    }

    private func refreshPlaybackState() {
        guard playbackRequested else {
            isPlaying = false
            isLoading = false
            return
        }
        guard let player else {
            isPlaying = false
            return
        }
        if player.timeControlStatus == .playing {
            isPlaying = true
            isLoading = false
        } else {
            isPlaying = false
            isLoading = true
        }
    }

    @discardableResult
    private func pausePlayback(cancelDownload: Bool = true) -> Bool {
        let hasPendingDownload = player == nil && (playbackRequested || isLoading)
        if hasPendingDownload && cancelDownload {
            downloadTask?.cancel()
            downloadToken = nil
            downloadTask = nil
        }
        guard player != nil || playbackRequested || isLoading else { return false }
        playbackRequested = false
        player?.pause()
        isPlaying = false
        if cancelDownload || player != nil {
            isLoading = false
        }
        updateNowPlayingInfo()
        return true
    }

    @discardableResult
    private func resumePlayback() -> Bool {
        guard let player else {
            if isLoading {
                playbackRequested = true
                updateNowPlayingInfo()
                return true
            }
            isPlaying = false
            if !isLoading { playbackRequested = false }
            updateNowPlayingInfo()
            return false
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        playbackRequested = true
        player.play()
        refreshPlaybackState()
        updateNowPlayingInfo()
        return true
    }

    @discardableResult
    func togglePlayPause() -> Bool {
        if playbackRequested || isPlaying {
            return pausePlayback()
        }
        return resumePlayback()
    }

    func playNext() {
        guard !queue.isEmpty else { return }
        currentIndex = resolvedCurrentQueueIndex ?? queue.startIndex
        if isShuffleOn, queue.count > 1 {
            var nextIndex = currentIndex
            while nextIndex == currentIndex {
                nextIndex = Int.random(in: 0 ..< queue.count)
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
            return
        }
        guard !queue.isEmpty else {
            player?.seek(to: .zero)
            return
        }
        if let index = resolvedCurrentQueueIndex {
            currentIndex = index
        }
        if currentIndex > 0 {
            currentIndex -= 1
            currentSong = queue[currentIndex]
            prepareAndPlay()
        } else {
            player?.seek(to: .zero)
        }
    }

    func playEnded() {
        if playbackMode == .singleLoop {
            player?.seek(to: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.player?.play()
                }
            }
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

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        player?.volume = Float(clamped)
        // Crown rotation streams values continuously; persist only the settled value.
        volumePersistWorkItem?.cancel()
        let item = DispatchWorkItem {
            UserDefaults.standard.set(clamped, forKey: AudioManager.volumeDefaultsKey)
        }
        volumePersistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private static func storedVolume() -> Double {
        guard UserDefaults.standard.object(forKey: volumeDefaultsKey) != nil else { return 1 }
        return min(max(UserDefaults.standard.double(forKey: volumeDefaultsKey), 0), 1)
    }

    private var resolvedCurrentQueueIndex: Int? {
        guard !queue.isEmpty, let currentSong else { return nil }
        if queue.indices.contains(currentIndex), queue[currentIndex] == currentSong {
            return currentIndex
        }
        return queue.firstIndex(of: currentSong)
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
        let storageKey = SongStorageKey.component(for: songID)
        return AudioManager.audioCacheDir.appendingPathComponent("\(storageKey).mp3")
    }

    private func finishDownloadedPlayback(
        tempURL: URL,
        responseAccepted: Bool,
        destinationURL: URL,
        song: Song
    ) {
        guard storeDownloadedAudio(
            tempURL: tempURL,
            responseAccepted: responseAccepted,
            destinationURL: destinationURL
        )
        else {
            playbackRequested = false
            return
        }
        guard currentSong?.id == song.id else { return }
        validateCachedFile(at: destinationURL, expectedDuration: song.duration) { [weak self] valid in
            guard let self, currentSong?.id == song.id else { return }
            guard valid else {
                try? FileManager.default.removeItem(at: destinationURL)
                playbackRequested = false
                return
            }
            evictOldCacheFiles()
            setupPlayer(with: destinationURL)
        }
    }

    private func storeDownloadedAudio(
        tempURL: URL,
        responseAccepted: Bool,
        destinationURL: URL
    ) -> Bool {
        guard responseAccepted, Self.hasValidAudioHeader(at: tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: destinationURL)
            return false
        }
    }

    private nonisolated static func acceptsAudioResponse(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        guard (200 ... 299).contains(http.statusCode) else { return false }
        if http.expectedContentLength > 256 * 1024 * 1024 {
            return false
        }
        guard let mimeType = http.mimeType?.lowercased(), !mimeType.isEmpty else { return true }
        return !mimeType.hasPrefix("text/")
            && mimeType != "application/json"
            && !mimeType.hasSuffix("+json")
    }

    private nonisolated static func hasValidAudioHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 12), header.count >= 4 else { return false }
        if header[0] == 0xFF, (header[1] & 0xE0) == 0xE0 { return true }
        if header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 { return true }
        if header[0] == 0x52, header[1] == 0x49, header[2] == 0x46, header[3] == 0x46 {
            return true
        }
        if header[0] == 0x46, header[1] == 0x4F, header[2] == 0x52, header[3] == 0x4D {
            return true
        }
        if header[0] == 0x63, header[1] == 0x61, header[2] == 0x66, header[3] == 0x66 {
            return true
        }
        if header[0] == 0x66, header[1] == 0x4C, header[2] == 0x61, header[3] == 0x43 {
            return true
        }
        if header.count >= 8,
           header[4] == 0x66, header[5] == 0x74, header[6] == 0x79, header[7] == 0x70
        {
            return true
        }
        return false
    }

    func clearCache() {
        downloadTask?.cancel()
        downloadToken = nil
        downloadTask = nil
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(
            at: AudioManager.audioCacheDir, includingPropertiesForKeys: nil
        ) {
            for url in entries {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func validateCachedFile(
        at url: URL, expectedDuration: Int, completion: @escaping (Bool) -> Void
    ) {
        Task {
            let asset = AVURLAsset(url: url)
            let expected = Double(expectedDuration)
            do {
                let loadedDuration = try await asset.load(.duration)
                let isPlayable = try await asset.load(.isPlayable)
                let actual = loadedDuration.seconds
                let durationOK: Bool = if expected > 5 {
                    actual.isFinite && actual >= expected * 0.9
                } else {
                    actual.isFinite && actual > 0
                }
                await MainActor.run {
                    completion(isPlayable && durationOK)
                }
            } catch {
                await MainActor.run {
                    completion(false)
                }
            }
        }
    }

    private func validateCacheAndPlay(song: Song, cacheURL: URL) {
        let songID = song.id
        validateCachedFile(at: cacheURL, expectedDuration: song.duration) { [weak self] valid in
            guard let self,
                  currentSong?.id == songID,
                  playbackRequested || isLoading
            else { return }
            if valid {
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()],
                    ofItemAtPath: cacheURL.path
                )
                setupPlayer(with: cacheURL)
                return
            }
            try? FileManager.default.removeItem(at: cacheURL)
            guard let remoteURL = song.audioURL else {
                isLoading = false
                playbackRequested = false
                return
            }
            let token = UUID()
            downloadToken = token
            downloadTask = URLSession.shared.downloadTask(with: remoteURL) {
                [weak self] tempURL, response, error in
                let responseAccepted = Self.acceptsAudioResponse(response)
                DispatchQueue.main.async {
                    guard let self,
                          self.downloadToken == token,
                          self.currentSong?.id == songID
                    else { return }
                    self.downloadToken = nil
                    self.downloadTask = nil
                    self.isLoading = false
                    guard let tempURL, error == nil else {
                        self.playbackRequested = false
                        return
                    }
                    self.finishDownloadedPlayback(
                        tempURL: tempURL,
                        responseAccepted: responseAccepted,
                        destinationURL: cacheURL,
                        song: song
                    )
                }
            }
            downloadTask?.resume()
        }
    }

    @discardableResult
    private func recoverFromBrokenCache(playbackURL: URL) -> Bool {
        guard playbackURL.path.hasPrefix(AudioManager.audioCacheDir.path),
              let song = currentSong,
              !recoveringFromBrokenCache.contains(song.id),
              let remoteURL = song.audioURL
        else { return false }
        let songID = song.id
        recoveringFromBrokenCache.insert(songID)
        try? FileManager.default.removeItem(at: playbackURL)
        cleanupPlayer()
        isLoading = true
        downloadTask?.cancel()
        downloadToken = nil
        let token = UUID()
        downloadToken = token
        downloadTask = URLSession.shared.downloadTask(with: remoteURL) {
            [weak self] tempURL, response, error in
            let responseAccepted = Self.acceptsAudioResponse(response)
            DispatchQueue.main.async {
                guard let self,
                      self.downloadToken == token,
                      self.currentSong?.id == songID
                else { return }
                self.downloadToken = nil
                self.downloadTask = nil
                self.isLoading = false
                guard let tempURL, error == nil else {
                    self.playbackRequested = false
                    return
                }
                self.finishDownloadedPlayback(
                    tempURL: tempURL,
                    responseAccepted: responseAccepted,
                    destinationURL: playbackURL,
                    song: song
                )
            }
        }
        downloadTask?.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.recoveringFromBrokenCache.remove(songID)
        }
        return true
    }

    private func evictOldCacheFiles() {
        let fm = FileManager.default
        let dir = AudioManager.audioCacheDir
        guard
            let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
            )
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
        func performOnMain(
            _ action: @escaping @MainActor () -> MPRemoteCommandHandlerStatus
        ) -> MPRemoteCommandHandlerStatus {
            if Thread.isMainThread {
                return MainActor.assumeIsolated { action() }
            }
            var status: MPRemoteCommandHandlerStatus = .commandFailed
            DispatchQueue.main.sync {
                status = MainActor.assumeIsolated { action() }
            }
            return status
        }

        let playTarget = cc.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                guard !self.playbackRequested else { return .commandFailed }
                return self.resumePlayback() ? .success : .commandFailed
            }
        }
        remoteCommandTargets.append((cc.playCommand, playTarget))
        let pauseTarget = cc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                guard self.playbackRequested else { return .commandFailed }
                return self.pausePlayback() ? .success : .commandFailed
            }
        }
        remoteCommandTargets.append((cc.pauseCommand, pauseTarget))
        let toggleTarget = cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                self.togglePlayPause() ? .success : .commandFailed
            }
        }
        remoteCommandTargets.append((cc.togglePlayPauseCommand, toggleTarget))
        let nextTarget = cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                self.playNext()
                return .success
            }
        }
        remoteCommandTargets.append((cc.nextTrackCommand, nextTarget))
        let previousTarget = cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                self.playPrevious()
                return .success
            }
        }
        remoteCommandTargets.append((cc.previousTrackCommand, previousTarget))
    }

    private func setupInterruptionHandler() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
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
            shouldResumeAfterInterruption = playbackRequested
            if playbackRequested {
                pausePlayback(cancelDownload: false)
            }
        case .ended:
            guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
            if opts.contains(.shouldResume), shouldResumeAfterInterruption {
                resumePlayback()
            }
            shouldResumeAfterInterruption = false
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
        for target in remoteCommandTargets {
            target.command.removeTarget(target.target)
        }
        player?.pause()
    }
}
