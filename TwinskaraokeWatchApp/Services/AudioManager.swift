import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import Observation

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
@Observable
class AudioManager {
    static let shared = AudioManager()
    var currentSong: Song? {
        didSet { refreshUpNext() }
    }
    var isPlaying = false
    var isLoading = false
    var currentTime: Double = 0
    var duration: Double = 0
    var queue: [Song] = [] {
        didSet { refreshUpNext() }
    }
    var currentIndex: Int = 0 {
        didSet { refreshUpNext() }
    }
    private(set) var upNextSongs: [Song] = []
    private(set) var queueSummaryText = String(localized: "End of queue")
    var playbackMode: PlaybackMode = .listLoop
    var isShuffleOn = false
    var volume: Double = AudioManager.storedVolume()
    private(set) var isRadioMode = false
    private(set) var cacheRevision = 0
    private var radioArtworkURL: URL?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endTimeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var playerCancellables = Set<AnyCancellable>()
    private var downloadTask: URLSessionDownloadTask?
    private var downloadToken: UUID?
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var recoveringFromBrokenCache: Set<String> = []
    private var volumePersistWorkItem: DispatchWorkItem?
    private var playbackRequested = false
    private var shouldResumeAfterInterruption = false
    private var radioStreamToken: UUID?
    private var isSessionActive = false
    private nonisolated static let audioCacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated static let maxCachedFiles = 10
    private nonisolated static let maxCacheBytes = 128 * 1024 * 1024
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
            queueSummaryText = String(localized: "End of queue")
            return
        }
        let nextIndex = index + 1
        guard nextIndex < queue.endIndex else {
            upNextSongs = []
            queueSummaryText = String(localized: "End of queue")
            return
        }
        let songs = Array(queue[nextIndex...])
        upNextSongs = songs
        let countText = songs.count == 1 ? String(localized: "1 song next") : String(localized: "\(songs.count) songs next")
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
    func playSong(at index: Int, context: [Song]) {
        guard context.indices.contains(index) else { return }
        queue = context
        currentIndex = index
        currentSong = context[index]
        prepareAndPlay()
    }
    func playUpNext(at offset: Int) {
        guard let baseIndex = resolvedCurrentQueueIndex else { return }
        let index = baseIndex + 1 + offset
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        currentSong = queue[index]
        prepareAndPlay()
    }

    func playRadio(streamURL: URL, song: Song, artworkURL: URL?) {
        if isRadioMode, player != nil, currentSong?.id == song.id {
            radioArtworkURL = artworkURL
            currentSong = song
            updateNowPlayingInfo()
            return
        }
        cleanupPlayer()
        downloadTask?.cancel()
        downloadToken = nil
        downloadTask = nil
        cancellables.removeAll()
        setupInterruptionHandler()

        isRadioMode = true
        radioArtworkURL = artworkURL
        queue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        currentSong = song
        playbackRequested = true
        isLoading = true
        startRadioStream(url: streamURL)
    }
    func updateRadioMetadata(song: Song, artworkURL: URL?) {
        guard isRadioMode else { return }
        radioArtworkURL = artworkURL
        currentSong = song
        updateNowPlayingInfo()
    }

    func stopRadio() {
        guard isRadioMode else { return }
        cleanupPlayer()
        isRadioMode = false
        radioArtworkURL = nil
        playbackRequested = false
        isPlaying = false
        isLoading = false
        currentSong = nil
        currentTime = 0
        duration = 0
        updateNowPlayingInfo()
    }
    private func activatePlaybackSession(then start: @escaping @MainActor () -> Void) {
        if isSessionActive {
            start()
            return
        }
        Task.detached(priority: .userInitiated) {
            let activated = Self.bringUpPlaybackSession()
            await MainActor.run { [weak self] in
                self?.isSessionActive = activated
                start()
            }
        }
    }
    private nonisolated static func startOffMainActor(_ player: AVPlayer) {
        Task.detached(priority: .userInitiated) {
            player.play()
        }
    }

    private nonisolated static func bringUpPlaybackSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }
    private func startRadioStream(url: URL) {
        let token = UUID()
        radioStreamToken = token
        let startingVolume = Float(volume)
        Task.detached(priority: .userInitiated) {
            let playerItem = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: playerItem)
            player.volume = startingVolume
            player.automaticallyWaitsToMinimizeStalling = true
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            let activated = Self.bringUpPlaybackSession()
            let shouldStart = await MainActor.run { [weak self] () -> Bool in
                guard let self, self.radioStreamToken == token else { return false }
                self.isSessionActive = activated
                self.adoptRadioPlayer(player, item: playerItem)
                return self.playbackRequested
            }
            guard shouldStart else { return }
            player.playImmediately(atRate: 1.0)
        }
    }

    private func adoptRadioPlayer(_ player: AVPlayer, item playerItem: AVPlayerItem) {
        self.player = player

        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .readyToPlay {
                    if playbackRequested, isSessionActive {
                        Self.startOffMainActor(player)
                    }
                    refreshPlaybackState()
                    updateNowPlayingInfo()
                } else if status == .failed {
                    stopRadio()
                }
            }
            .store(in: &playerCancellables)
        player.publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPlaybackState()
            }
            .store(in: &playerCancellables)
    }

    private func prepareAndPlay() {
        isRadioMode = false
        radioArtworkURL = nil
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
        RecentlyPlayedStore.shared.record(song)
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
        startDownload(song: song, remoteURL: remoteURL, destinationURL: localURL)
    }
    private func startDownload(song: Song, remoteURL: URL, destinationURL: URL) {
        let token = UUID()
        downloadToken = token
        downloadTask = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, response, error in
            // URLSession deletes the downloaded file the moment this handler
            // returns, so the header check and the move have to happen here
            // rather than after a hop to the main queue. Doing them over there
            // is what silenced every non-radio song on device: the file was
            // already gone, so the header read failed and playback was dropped
            // without a spinner, an error, or a sound.
            let stored: Bool
            if let tempURL, error == nil, Self.acceptsAudioResponse(response) {
                stored = Self.storeDownloadedAudio(tempURL: tempURL, destinationURL: destinationURL)
            } else {
                if let tempURL {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                stored = false
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.downloadToken == token,
                      self.currentSong?.id == song.id
                else { return }
                self.downloadToken = nil
                self.downloadTask = nil
                guard stored else {
                    self.isLoading = false
                    self.playbackRequested = false
                    return
                }
                self.finishDownloadedPlayback(destinationURL: destinationURL, song: song)
            }
        }
        downloadTask?.resume()
    }

    private func setupPlayer(with localURL: URL) {
        cleanupPlayer()
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
            .store(in: &playerCancellables)
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .readyToPlay {
                    if playbackRequested, isSessionActive {
                        Self.startOffMainActor(player)
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
            .store(in: &playerCancellables)
        player.publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPlaybackState()
            }
            .store(in: &playerCancellables)
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
        activatePlaybackSession { [weak self] in
            guard let self,
                  self.player === player,
                  self.playbackRequested,
                  playerItem.status == .readyToPlay
            else { return }
            Self.startOffMainActor(player)
            self.refreshPlaybackState()
            self.updateNowPlayingInfo()
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
            if isRadioMode {
                isPlaying = false
                playbackRequested = false
                return false
            }
            if currentSong != nil {
                prepareAndPlay()
                return true
            }
            isPlaying = false
            playbackRequested = false
            updateNowPlayingInfo()
            return false
        }
        playbackRequested = true
        activatePlaybackSession { [weak self] in
            guard let self, self.player === player, self.playbackRequested else { return }
            Self.startOffMainActor(player)
            self.refreshPlaybackState()
            self.updateNowPlayingInfo()
        }
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
        guard !isRadioMode else { return }
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
        guard !isRadioMode else { return }
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
            let loopingPlayer = player
            loopingPlayer?.seek(to: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.player === loopingPlayer,
                          self.playbackRequested
                    else { return }
                    loopingPlayer?.play()
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
        guard !isRadioMode else { return }
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        updateNowPlayingInfo()
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        player?.volume = Float(clamped)
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
        playerCancellables.removeAll()
        radioStreamToken = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
            endTimeObserver = nil
        }
        if let retired = player {
            player = nil
            Task.detached(priority: .userInitiated) {
                retired.pause()
            }
        }
    }

    private func localCacheURL(for songID: String) -> URL {
        let storageKey = SongStorageKey.component(for: songID)
        return AudioManager.audioCacheDir.appendingPathComponent("\(storageKey).mp3")
    }

    private func finishDownloadedPlayback(destinationURL: URL, song: Song) {
        validateCachedFile(at: destinationURL, expectedDuration: song.duration) { [weak self] valid in
            guard let self, currentSong?.id == song.id else { return }
            guard valid else {
                try? FileManager.default.removeItem(at: destinationURL)
                noteCacheChanged()
                isLoading = false
                playbackRequested = false
                return
            }
            evictOldCacheFiles()
            noteCacheChanged()
            setupPlayer(with: destinationURL)
        }
    }
    nonisolated static func storeDownloadedAudio(
        tempURL: URL,
        destinationURL: URL
    ) -> Bool {
        guard hasValidAudioHeader(at: tempURL) else {
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
        noteCacheChanged()
    }
    private func noteCacheChanged() {
        cacheRevision &+= 1
    }
    nonisolated static func cacheSizeBytes(in directory: URL = audioCacheDir) -> Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return entries.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
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
            noteCacheChanged()
            guard let remoteURL = song.audioURL else {
                isLoading = false
                playbackRequested = false
                return
            }
            startDownload(song: song, remoteURL: remoteURL, destinationURL: cacheURL)
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
        noteCacheChanged()
        cleanupPlayer()
        cancellables.removeAll()
        setupInterruptionHandler()
        isLoading = true
        downloadTask?.cancel()
        downloadToken = nil
        startDownload(song: song, remoteURL: remoteURL, destinationURL: playbackURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.recoveringFromBrokenCache.remove(songID)
        }
        return true
    }
    func evictOldCacheFiles(
        in directory: URL = AudioManager.audioCacheDir,
        maxCount: Int = AudioManager.maxCachedFiles,
        maxBytes: Int = AudioManager.maxCacheBytes
    ) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard
            let files = try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys
            )
        else { return }
        let keySet = Set(keys)
        let sorted = files
            .map { url -> (url: URL, date: Date, size: Int) in
                let values = try? url.resourceValues(forKeys: keySet)
                return (
                    url: url,
                    date: values?.contentModificationDate ?? .distantPast,
                    size: values?.fileSize ?? 0
                )
            }
            .sorted { $0.date < $1.date }
        var keptCount = 0
        var keptBytes = 0
        for (index, entry) in sorted.reversed().enumerated() {
            let file = entry.url
            let size = entry.size
            if index == 0 || (keptCount < maxCount && keptBytes + size <= maxBytes) {
                keptCount += 1
                keptBytes += size
            } else {
                try? fm.removeItem(at: file)
            }
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
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleRouteChange(note) }
            .store(in: &cancellables)
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            isSessionActive = false
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
    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable,
              playbackRequested
        else { return }
        pausePlayback(cancelDownload: false)
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
        if let artwork = nowPlayingArtwork(for: song) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func nowPlayingArtwork(for song: Song) -> MPMediaItemArtwork? {
        guard let url = isRadioMode ? radioArtworkURL : song.thumbnailURL else { return nil }
        if let image = WatchImageCache.shared.cachedImage(for: url) {
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        Task { [weak self] in
            guard let self,
                  await WatchImageCache.shared.image(for: url) != nil,
                  self.currentSong?.id == song.id
            else { return }
            self.updateNowPlayingInfo()
        }
        return nil
    }

    isolated deinit {
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
