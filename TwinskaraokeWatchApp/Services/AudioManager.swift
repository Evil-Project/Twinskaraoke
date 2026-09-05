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
    /// Up-next slice of the queue plus its summary string, recomputed only when
    /// the queue or current track changes (views re-evaluate on every 0.5s tick).
    private(set) var upNextSongs: [Song] = []
    private(set) var queueSummaryText = "End of queue"
    var playbackMode: PlaybackMode = .listLoop
    var isShuffleOn = false
    var volume: Double = AudioManager.storedVolume()
    /// Live radio plays a stream straight from the network instead of going
    /// through the download-then-play cache pipeline, and has no queue,
    /// duration, or seekable position. Everything that assumes those is gated
    /// on this.
    private(set) var isRadioMode = false
    /// Bumped whenever the downloaded-audio cache gains or loses a file.
    ///
    /// The size itself is not published, because working it out means walking
    /// the directory and almost nobody is looking. This is the cheap signal a
    /// screen that *is* looking can watch, so a download finishing behind the
    /// Account screen updates the figure on it instead of leaving it stale
    /// until the listener navigates away and back.
    private(set) var cacheRevision = 0
    /// Radio artwork comes from the station metadata, not from `Song`, which
    /// carries only a synthetic ID for the current track.
    private var radioArtworkURL: URL?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endTimeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    // Player-item/player publishers live here so cleanupPlayer can drop them
    // without touching the audio-session handlers in `cancellables`.
    private var playerCancellables = Set<AnyCancellable>()
    private var downloadTask: URLSessionDownloadTask?
    private var downloadToken: UUID?
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var recoveringFromBrokenCache: Set<String> = []
    private var volumePersistWorkItem: DispatchWorkItem?
    private var playbackRequested = false
    private var shouldResumeAfterInterruption = false
    /// Identifies the tune-in a stream is being built for, so a station the
    /// listener has already left behind can't adopt itself when it finishes
    /// coming up on its own queue.
    private var radioStreamToken: UUID?
    /// Whether the playback session is up. A player told to play against an
    /// inactive session just sits there, so every `play()` waits on this.
    private var isSessionActive = false
    private nonisolated static let audioCacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated static let maxCachedFiles = 10
    /// Total on-disk budget for the audio cache: once past it, the oldest
    /// files are evicted even when the count limit has not been reached.
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

    /// Plays the song at `index` in `context`. The position is picked by
    /// index rather than by song lookup so tapping a repeated song targets
    /// that occurrence instead of the first match in the context.
    func playSong(at index: Int, context: [Song]) {
        guard context.indices.contains(index) else { return }
        queue = context
        currentIndex = index
        currentSong = context[index]
        prepareAndPlay()
    }

    /// Plays the up-next row at `offset`. The queue position is picked by
    /// offset rather than by song lookup so tapping a repeated song targets
    /// that occurrence instead of the first match in the queue.
    func playUpNext(at offset: Int) {
        guard let baseIndex = resolvedCurrentQueueIndex else { return }
        let index = baseIndex + 1 + offset
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        currentSong = queue[index]
        prepareAndPlay()
    }

    // MARK: - Live radio

    func playRadio(streamURL: URL, song: Song, artworkURL: URL?) {
        // Already tuned in: the track changed under us, not the station.
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
        // A stream has no queue to advance through and no position to scrub.
        queue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        currentSong = song
        playbackRequested = true
        isLoading = true
        startRadioStream(url: streamURL)
    }

    /// Applies a metadata poll to the track already playing, without touching
    /// the stream itself.
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

    /// Brings the playback session up away from the main actor, then runs
    /// `start` back on it.
    ///
    /// AVFoundation documents activation as "a synchronous (blocking)
    /// operation" and warns against running it anywhere a long block is a
    /// problem. On a watch the main actor is exactly that place: tuning the
    /// radio stalled the whole app for a beat, right when it had the most
    /// drawing to do. Once the session is up the hop is skipped, so play/pause
    /// stays immediate.
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

    /// Starts a player away from the main actor.
    ///
    /// `play` is `NS_SWIFT_NONISOLATED` like the rest of AVPlayer's transport:
    /// it is the call that actually opens the route, and the one worth keeping
    /// off the actor that has to keep drawing while it happens.
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

    /// Opens the live stream without holding onto the main actor.
    ///
    /// AVFoundation marks every call in here `NS_SWIFT_NONISOLATED` — building
    /// the item, building the player, starting it — so none of it belongs on
    /// the main actor, and on a watch that is not a nicety. Opening a stream
    /// goes out to the media daemon and back, and doing that from the main
    /// actor is what froze the whole app for a beat the moment Listen Live was
    /// tapped. The buffering spinner the radio screen already draws is free to
    /// animate while this runs.
    private func startRadioStream(url: URL) {
        let token = UUID()
        radioStreamToken = token
        let startingVolume = Float(volume)
        Task.detached(priority: .userInitiated) {
            let playerItem = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: playerItem)
            player.volume = startingVolume
            // A live stream is better served by waiting out a stall than by
            // dropping back to the start of the buffer.
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
                    // The session may still be coming up on its own queue; it
                    // starts playback itself when it lands.
                    if playbackRequested, isSessionActive {
                        Self.startOffMainActor(player)
                    }
                    refreshPlaybackState()
                    updateNowPlayingInfo()
                } else if status == .failed {
                    // No cache to fall back on and no next track to skip to:
                    // surface it as stopped and let the listener retry.
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
        // Any ordinary song leaves the station behind; this is the single
        // funnel every play path goes through.
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
        // Every play path funnels through here, so recents are recorded once
        // rather than at each of the four call sites that set `currentSong`.
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

    /// Single download/validate/play pipeline: every path that fetches remote
    /// audio (fresh play, cache re-download, broken-cache recovery) goes
    /// through here so fixes apply in one place.
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
                // `isLoading` stays set until the player takes over: validation
                // is another async hop, and dropping the spinner here would
                // flash the idle controls in between.
                self.finishDownloadedPlayback(destinationURL: destinationURL, song: song)
            }
        }
        downloadTask?.resume()
    }

    private func setupPlayer(with localURL: URL) {
        // Raced async cache validations can both reach here for one song;
        // tear down any existing player and its observers so two players
        // never run at once and no orphaned observer keeps firing.
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
                    // The session may still be coming up on its own queue; it
                    // starts playback itself when it lands.
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
        // Whichever of these lands second starts playback: the item may go
        // ready before the session is up, or the other way round.
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
            // A dead radio player has nothing to restart from: there is no
            // downloadable URL behind it, and `prepareAndPlay` would file the
            // station's synthetic song into recently played.
            if isRadioMode {
                isPlaying = false
                playbackRequested = false
                return false
            }
            // Pausing during the initial download cancelled it with nothing
            // in flight; restart the prepare/download pipeline instead of
            // dead-ending.
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
        // Seeking a live stream would drop back into the buffer rather than
        // restart anything, and there is no queue behind it.
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
            // The seek completes asynchronously; only resume if this is still
            // the active player and the user has not paused/skipped meanwhile.
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
        // A live stream has no meaningful position to seek to.
        guard !isRadioMode else { return }
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
        // Drop the player's Combine sinks first: a raced second setupPlayer
        // would otherwise leave the old player's status callbacks firing
        // against the replacement.
        playerCancellables.removeAll()
        // Any stream still being built is for a station we have now left.
        radioStreamToken = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
            endTimeObserver = nil
        }
        // Retiring a player reaches the media daemon the same way starting one
        // does, and it happens on the way *into* the next track — so it is off
        // the main actor too, holding the last reference until it is done.
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

    /// Validates and files a finished download. Runs on URLSession's queue,
    /// inside the completion handler, because that is the only window in which
    /// `tempURL` still exists.
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

    /// Tells anyone displaying the cache that the figure they have is old.
    private func noteCacheChanged() {
        cacheRevision &+= 1
    }

    /// Bytes currently held by the downloaded-audio cache.
    ///
    /// Walks the directory on each call rather than tracking a running total:
    /// eviction, playback and manual clearing all mutate it, and the only
    /// caller is a settings screen the listener has to deliberately open.
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
        // As in prepareAndPlay, drop the dead player's Combine sinks; this
        // also drops the session handlers, so re-register them.
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

    /// Evicts least-recently-played cache files once either the file-count
    /// limit or the total byte budget is exceeded. The newest file (usually
    /// the one just downloaded) is always kept.
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
        // Oldest first; both budgets drop the least-recently-played files.
        // Stat each file once up front rather than inside the comparator, which
        // would re-hit the filesystem twice per comparison.
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
            // The system takes the session away with the interruption, so the
            // next resume has to bring it back up rather than assume it is there.
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

    /// Mirrors the iOS route-change handling: when the current output device
    /// goes away (headphones disconnected), pause instead of continuing on
    /// the watch speaker.
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

    /// Now Playing artwork served from the image cache the player view
    /// already warms; falls back to no artwork until the thumbnail arrives.
    private func nowPlayingArtwork(for song: Song) -> MPMediaItemArtwork? {
        // A radio track's `Song` is synthesised from station metadata and has
        // no artwork path of its own.
        guard let url = isRadioMode ? radioArtworkURL : song.thumbnailURL else { return nil }
        if let image = WatchImageCache.shared.cachedImage(for: url) {
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        // Not cached yet: fetch, then re-apply so the artwork appears without
        // waiting for the next playback event.
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
