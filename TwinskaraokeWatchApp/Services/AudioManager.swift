import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import Observation

/// Matches the phone: both modes repeat the current song, `.all` until it
/// is turned off and `.one` once more before switching itself off.
enum PlaybackMode {
    case off
    case one
    case all
    var iconName: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }
    var isActive: Bool { self != .off }
    var accessibilityValue: String {
        switch self {
        case .off: String(localized: "Off")
        case .one: String(localized: "Repeat Once")
        case .all: String(localized: "Repeat")
        }
    }
    var next: PlaybackMode {
        switch self {
        case .off: .one
        case .one: .all
        case .all: .off
        }
    }
}

@MainActor
@Observable
class AudioManager {
    static let shared = AudioManager()
    var currentSong: Song? {
        didSet { refreshUpNext(); WatchAuthManager.shared.localPlaybackDidChange() }
    }
    var isPlaying = false { didSet { if oldValue != isPlaying { WatchAuthManager.shared.localPlaybackDidChange() } } }
    var isLoading = false
    var playbackError: String?
    var currentTime: Double = 0 { didSet { WatchAuthManager.shared.localPlaybackDidChange(periodic: true) } }
    var duration: Double = 0
    var queue: [Song] = [] {
        didSet { refreshUpNext(); WatchAuthManager.shared.localPlaybackDidChange() }
    }
    var currentIndex: Int = 0 {
        didSet { refreshUpNext(); WatchAuthManager.shared.localPlaybackDidChange() }
    }
    /// Up-next slice of the queue plus its summary string, recomputed only when
    /// the queue or current track changes (views re-evaluate on every 0.5s tick).
    private(set) var upNextSongs: [Song] = []
    private(set) var queueSummaryText = String(localized: "End of queue")
    var playbackMode: PlaybackMode = .off { didSet { WatchAuthManager.shared.localPlaybackDidChange() } }
    private var originalQueue: [Song] = []
    var isShuffleOn = false { didSet { WatchAuthManager.shared.localPlaybackDidChange() } }
    var volume: Double = AudioManager.storedVolume()
    /// Live radio streams without a downloadable offline copy, and has no queue,
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
    private var radioStreamURL: URL?
    private var transferredPosition: Double?
    @ObservationIgnored private var companionProgressTimer: Timer?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endTimeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    // Player-item/player publishers live here so cleanupPlayer can drop them
    // without touching the audio-session handlers in `cancellables`.
    private var playerCancellables = Set<AnyCancellable>()
    private var metadataToken: UUID?
    private var startupTimeout: Task<Void, Never>?
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

    @ObservationIgnored private(set) lazy var sleepTimer = SleepTimer { [weak self] in
        _ = self?.pausePlayback()
        WatchAuthManager.shared.localPlaybackDidChange()
    }

    func setSleepTimer(minutes: Int? = nil, endOfSong: Bool = false) {
        if WatchAuthManager.shared.output == .phone {
            _ = WatchAuthManager.shared.sendPlaybackCommand(CompanionPlayback.Command(
                sessionID: WatchAuthManager.shared.currentPlaybackSessionID,
                action: .sleepTimer, sleepMinutes: minutes, sleepAtEndOfSong: endOfSong))
            return
        }
        guard WatchAuthManager.shared.canPlayLocally else { return }
        sleepTimer.cancel()
        if endOfSong { sleepTimer.startEndOfSong() }
        else if let minutes { sleepTimer.start(minutes: minutes) }
        WatchAuthManager.shared.localPlaybackDidChange()
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

    private func sendToPhone(
        _ action: CompanionPlayback.Action,
        song: Song? = nil,
        queue: [Song]? = nil,
        position: Double? = nil,
        streamURL: URL? = nil,
        artworkURL: URL? = nil,
        shuffleEnabled: Bool? = nil
    ) -> Bool {
        if WatchAuthManager.shared.changingOutput {
            playbackError = String(localized: "Changing audio output. Try again in a moment.")
            return true
        }
        guard WatchAuthManager.shared.output == .phone else {
            if !WatchAuthManager.shared.canPlayLocally {
                playbackError = "Reconnect to iPhone to finish changing output, then select Apple Watch again."
                return true
            }
            return false
        }
        let command = CompanionPlayback.Command(
            sessionID: WatchAuthManager.shared.currentPlaybackSessionID,
            action: action, song: song, queue: queue, position: position,
            streamURL: streamURL, artworkURL: artworkURL, shuffleEnabled: shuffleEnabled
        )
        return WatchAuthManager.shared.sendPlaybackCommand(command)
    }

    func stopForOutputTransfer() {
        sleepTimer.cancel()
        playbackRequested = false
        shouldResumeAfterInterruption = false
        metadataToken = nil
        cleanupPlayer()
        companionProgressTimer?.invalidate()
        companionProgressTimer = nil
        isPlaying = false
        isLoading = false
        isSessionActive = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func clearAccountPlayback() {
        stopForOutputTransfer()
        currentSong = nil
        queue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        isRadioMode = false
        radioStreamURL = nil
        radioArtworkURL = nil
        transferredPosition = nil
    }

    func localSnapshot(lease: CompanionPlayback.Lease, revision: Int) -> CompanionPlayback.Snapshot {
        CompanionPlayback.Snapshot(sessionID: lease.sessionID, revision: revision, owner: .watch,
            song: currentSong, queue: queue, isPlaying: isPlaying,
            isRadio: isRadioMode, radioArtworkURL: radioArtworkURL,
            position: currentTime.isFinite ? currentTime : 0, duration: duration.isFinite ? duration : 0,
            isShuffled: isShuffleOn,
            repeatSetting: playbackMode == .one ? .one : (playbackMode == .all ? .all : .off),
            error: playbackError, updatedAt: Date(), ownershipEpoch: lease.epoch, radioStreamURL: radioStreamURL,
            sleepDeadline: sleepTimer.deadline, sleepAtEndOfSong: sleepTimer.endsWithCurrentSong)
    }

    func applyRemoteCommand(_ command: CompanionPlayback.Command) {
        guard WatchAuthManager.shared.canPlayLocally else { return }
        switch command.action {
        case .play:
            if let shuffled = command.shuffleEnabled { isShuffleOn = shuffled }
            if let song = command.song { play(song: song, context: command.queue ?? [song]) }
        case .sleepTimer: setSleepTimer(minutes: command.sleepMinutes, endOfSong: command.sleepAtEndOfSong == true)
        case .pause: _ = pausePlayback()
        case .resume: _ = resumePlayback()
        case .next: playNext()
        case .previous: playPrevious()
        case .seek: if let time = command.position, time.isFinite { seek(to: time) }
        case .shuffle: toggleShuffle()
        case .repeatMode: toggleMode()
        case .radio:
            if let song = command.song, let url = command.streamURL {
                playRadio(streamURL: url, song: song, artworkURL: command.artworkURL)
            }
        case .stopRadio: stopRadio()
        case .replaceQueue: queue = command.queue ?? []
        case .playNext, .playLast:
            if let song = command.song {
                let index = command.action == .playNext ? min(currentIndex + 1, queue.count) : queue.count
                queue.insert(song, at: index)
            }
        case .transferToPhone, .transferToWatch: break
        }
    }

    func applyCompanionSnapshot(_ snapshot: CompanionPlayback.Snapshot) {
        if snapshot.owner == .watch {
            sleepTimer.cancel()
            if let deadline = snapshot.sleepDeadline { sleepTimer.start(deadline: deadline) }
            else if snapshot.sleepAtEndOfSong == true { sleepTimer.startEndOfSong() }
        } else {
            sleepTimer.mirror(deadline: snapshot.sleepDeadline, endsWithCurrentSong: snapshot.sleepAtEndOfSong == true)
        }
        // A companion snapshot only updates presentation. It must never open a
        // player on the watch while the phone owns audio.
        if player != nil { cleanupPlayer() }
        metadataToken = nil
        playbackRequested = false
        // Position snapshots arrive frequently. Replacing the whole queue and
        // song on each tick makes watchOS rebuild an active NavigationStack and
        // page view while it is animating into Now Playing.
        if currentSong?.id != snapshot.song?.id
            || currentSong?.title != snapshot.song?.title
            || currentSong?.artistName != snapshot.song?.artistName
            || currentSong?.thumbnailURL != snapshot.song?.thumbnailURL {
            currentSong = snapshot.song
        }
        if queue != snapshot.queue { queue = snapshot.queue }
        let index = snapshot.song.flatMap { song in queue.firstIndex(of: song) } ?? 0
        if currentIndex != index { currentIndex = index }
        if isRadioMode != snapshot.isRadio { isRadioMode = snapshot.isRadio }
        if radioArtworkURL != snapshot.radioArtworkURL { radioArtworkURL = snapshot.radioArtworkURL }
        radioStreamURL = snapshot.radioStreamURL
        if snapshot.owner == .watch {
            companionProgressTimer?.invalidate()
            companionProgressTimer = nil
            transferredPosition = snapshot.position
            isPlaying = false
        } else if isPlaying != snapshot.isPlaying { isPlaying = snapshot.isPlaying }
        if isLoading { isLoading = false }
        currentTime = snapshot.position.isFinite ? max(0, snapshot.position) : 0
        duration = snapshot.duration.isFinite ? max(0, snapshot.duration) : 0
        if isShuffleOn != snapshot.isShuffled { isShuffleOn = snapshot.isShuffled }
        switch snapshot.repeatSetting {
        case .off: playbackMode = .off
        case .one: playbackMode = .one
        case .all: playbackMode = .all
        }
        playbackError = snapshot.error
        if snapshot.owner == .phone, companionProgressTimer == nil {
            companionProgressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isPlaying, !self.isRadioMode else { return }
                    self.currentTime = min(self.currentTime + 1, self.duration)
                }
            }
        }
    }

    private func failPlayback(_ message: String) {
        cleanupPlayer()
        playbackRequested = false
        isPlaying = false
        isLoading = false
        if isRadioMode { isRadioMode = false }
        playbackError = message
        updateNowPlayingInfo()
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

    func play(song: Song, context: [Song] = [], shuffled: Bool? = nil) {
        if let shuffled { isShuffleOn = shuffled }
        transferredPosition = nil
        var playbackQueue = context.isEmpty ? [song] : context
        if let index = playbackQueue.firstIndex(of: song) {
            currentIndex = index
        } else {
            playbackQueue.insert(song, at: 0)
            currentIndex = 0
        }
        queue = playbackQueue
        currentSong = song
        playbackError = nil
        if sendToPhone(.play, song: song, queue: playbackQueue, shuffleEnabled: shuffled ?? isShuffleOn) {
            isLoading = playbackError == nil
            return
        }
        if isShuffleOn {
            originalQueue = playbackQueue
            queue = [song] + playbackQueue.filter { $0.id != song.id }.shuffled()
            currentIndex = 0
        } else { originalQueue = [] }
        prepareAndPlay()
    }

    /// Plays the song at `index` in `context`. The position is picked by
    /// index rather than by song lookup so tapping a repeated song targets
    /// that occurrence instead of the first match in the context.
    func playSong(at index: Int, context: [Song]) {
        transferredPosition = nil
        guard context.indices.contains(index) else { return }
        queue = context
        currentIndex = index
        currentSong = context[index]
        playbackError = nil
        if sendToPhone(.play, song: context[index], queue: context) {
            isLoading = playbackError == nil
            return
        }
        prepareAndPlay()
    }

    /// Plays the up-next row at `offset`. The queue position is picked by
    /// offset rather than by song lookup so tapping a repeated song targets
    /// that occurrence instead of the first match in the queue.
    func playUpNext(at offset: Int) {
        transferredPosition = nil
        guard let baseIndex = resolvedCurrentQueueIndex else { return }
        let index = baseIndex + 1 + offset
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        currentSong = queue[index]
        playbackError = nil
        if sendToPhone(.play, song: queue[index], queue: queue) {
            isLoading = playbackError == nil
            return
        }
        prepareAndPlay()
    }

    // MARK: - Live radio

    func playRadio(streamURL: URL, song: Song, artworkURL: URL?) {
        playbackError = nil
        if sendToPhone(.radio, song: song, streamURL: streamURL, artworkURL: artworkURL) {
            if playbackError == nil {
                currentSong = song
                isRadioMode = true
                isLoading = true
            }
            return
        }
        radioStreamURL = streamURL
        // Already tuned in: the track changed under us, not the station.
        if isRadioMode, player != nil, currentSong?.id == song.id {
            radioArtworkURL = artworkURL
            currentSong = song
            updateNowPlayingInfo()
            return
        }
        cleanupPlayer()
        metadataToken = nil
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
        guard WatchAuthManager.shared.canPlayLocally, isRadioMode else { return }
        radioArtworkURL = artworkURL
        currentSong = song
        updateNowPlayingInfo()
    }

    func stopRadio() {
        guard isRadioMode else { return }
        if sendToPhone(.stopRadio) { return }
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
            let activated = await Self.bringUpPlaybackSession()
            await MainActor.run { [weak self] in
                self?.isSessionActive = activated
                guard activated else {
                    self?.failPlayback(String(localized: "Audio is unavailable. Connect an audio output and try again."))
                    return
                }
                start()
            }
        }
    }

    /// Keep transport ordered with pause and cleanup on the main actor.
    private static func startPlayer(_ player: AVPlayer) {
        player.play()
    }

    private nonisolated static func bringUpPlaybackSession() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            return await withCheckedContinuation { continuation in
                session.activate(options: []) { @Sendable success, _ in
                    continuation.resume(returning: success)
                }
            }
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
        let startingVolume: Float = 1
        Task.detached(priority: .userInitiated) {
            let playerItem = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: playerItem)
            player.volume = startingVolume
            // A live stream is better served by waiting out a stall than by
            // dropping back to the start of the buffer.
            player.automaticallyWaitsToMinimizeStalling = true
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            let activated = await Self.bringUpPlaybackSession()
            await MainActor.run { [weak self] in
                guard let self, self.radioStreamToken == token, WatchAuthManager.shared.canPlayLocally else { return }
                self.isSessionActive = activated
                guard activated else {
                    self.failPlayback(String(localized: "Audio is unavailable. Connect an audio output and try again."))
                    return
                }
                self.adoptRadioPlayer(player, item: playerItem)
                if self.playbackRequested { Self.startPlayer(player) }
            }
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
                        Self.startPlayer(player)
                    }
                    refreshPlaybackState()
                    updateNowPlayingInfo()
                } else if status == .failed {
                    failPlayback(String(localized: "Radio couldn't start. Check your connection and try again."))
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
        guard WatchAuthManager.shared.canPlayLocally else { return }
        companionProgressTimer?.invalidate()
        companionProgressTimer = nil
        // Any ordinary song leaves the station behind; this is the single
        // funnel every play path goes through.
        isRadioMode = false
        radioArtworkURL = nil
        cleanupPlayer()
        currentTime = 0
        duration = 0
        isPlaying = false
        playbackRequested = true
        playbackError = nil
        cancellables.removeAll()
        setupInterruptionHandler()
        metadataToken = nil
        guard let song = currentSong else {
            playbackRequested = false
            isLoading = false
            return
        }
        // Every play path funnels through here, so recents are recorded once
        // rather than at each of the four call sites that set `currentSong`.
        RecentlyPlayedStore.shared.record(song)
        let localURL = WatchDownloads.shared.localURL(for: song.id) ?? localCacheURL(for: song.id)
        if FileManager.default.fileExists(atPath: localURL.path) {
            isLoading = true
            validateCacheAndPlay(song: song, cacheURL: localURL)
            return
        }
        guard let remoteURL = song.audioURL else {
            isLoading = true
            let token = UUID()
            metadataToken = token
            Task { [weak self] in
                do {
                    let canonical = try await KaraokeAPIClient.fetchSong(id: song.id)
                    guard let self, self.metadataToken == token, self.currentSong?.id == song.id,
                          WatchAuthManager.shared.canPlayLocally else { return }
                    let resolved = song.fillingMissingMetadata(from: canonical)
                    guard let url = resolved.audioURL else {
                        self.failPlayback("This song has no playable audio. Choose another song.")
                        return
                    }
                    self.currentSong = resolved
                    self.metadataToken = nil
                    self.setupPlayer(with: url)
                } catch {
                    guard let self, self.metadataToken == token else { return }
                    self.failPlayback("Couldn't load this song's audio. Sync your iPhone account and try again.")
                }
            }
            return
        }
        isLoading = true
        setupPlayer(with: remoteURL)
    }

    // Uncached songs stream through AVPlayer, whose media transport remains
    // active with background audio. Explicit offline copies use the watch's
    // background URLSession download service, rather than a foreground task
    // that can stall or be suspended before an entire song is downloaded.
    private func setupPlayer(with localURL: URL) {
        guard WatchAuthManager.shared.canPlayLocally, playbackRequested else { return }
        // Raced async cache validations can both reach here for one song;
        // tear down any existing player and its observers so two players
        // never run at once and no orphaned observer keeps firing.
        cleanupPlayer()
        let playerItem = AVPlayerItem(url: localURL)
        let player = AVPlayer(playerItem: playerItem)
        player.volume = 1
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        startupTimeout = Task { [weak self, weak player] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, let player, self.player === player, self.playbackRequested,
                  !self.isPlaying else { return }
            self.failPlayback("Audio didn't start. Check your watch connection and Bluetooth output, then tap Play to retry.")
        }
        if let position = transferredPosition, position.isFinite, position > 0 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        transferredPosition = nil
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
                        Self.startPlayer(player)
                    }
                    refreshPlaybackState()
                    updateNowPlayingInfo()
                } else if status == .failed {
                    isLoading = false
                    isPlaying = false
                    if !recoverFromBrokenCache(playbackURL: localURL) {
                        failPlayback(localURL.isFileURL
                            ? "This downloaded song couldn't play. Remove it and download it again."
                            : "Couldn't stream this song. Check watch Wi-Fi or cellular and your audio output, then try again.")
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
            Self.startPlayer(player)
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
            startupTimeout?.cancel()
            startupTimeout = nil
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
            metadataToken = nil
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
        guard WatchAuthManager.shared.canPlayLocally else { return false }
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
                guard let song = currentSong, let url = radioStreamURL else {
                    failPlayback("Choose the radio station again to start playback.")
                    return false
                }
                playRadio(streamURL: url, song: song, artworkURL: radioArtworkURL)
                return true
            }
            // Restart a cancelled metadata lookup or a failed media startup.
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
            Self.startPlayer(player)
            self.refreshPlaybackState()
            self.updateNowPlayingInfo()
        }
        refreshPlaybackState()
        updateNowPlayingInfo()
        return true
    }

    @discardableResult
    func togglePlayPause() -> Bool {
        if let song = currentSong,
           WatchAuthManager.shared.currentPlaybackSongID != song.id,
           sendToPhone(.play, song: song, queue: queue) {
            return playbackError == nil
        }
        if sendToPhone(isPlaying ? .pause : .resume) { return playbackError == nil }
        if playbackRequested || isPlaying {
            return pausePlayback()
        }
        return resumePlayback()
    }

    /// Next on the last song stops, as the song ending there does. Like the
    /// phone, Next never wraps to the start of the queue.
    func playNext() {
        transferredPosition = nil
        if sendToPhone(.next) { return }
        guard !isRadioMode else { return }
        guard !queue.isEmpty else { return }
        currentIndex = resolvedCurrentQueueIndex ?? queue.startIndex
        guard currentIndex + 1 < queue.count else {
            _ = pausePlayback()
            return
        }
        currentIndex += 1
        currentSong = queue[currentIndex]
        prepareAndPlay()
    }

    func playPrevious() {
        transferredPosition = nil
        if sendToPhone(.previous) { return }
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
        if sleepTimer.consumeEndOfSong() {
            _ = pausePlayback()
            return
        }
        if playbackMode.isActive {
            // The replay spends Repeat Once.
            if playbackMode == .one { playbackMode = .off }
            // The seek completes asynchronously; only resume if this is still
            // the active player and the user has not paused/skipped meanwhile.
            let loopingPlayer = player
            loopingPlayer?.seek(to: .zero) { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.player === loopingPlayer,
                          self.playbackRequested
                    else { return }
                    loopingPlayer?.play()
                    // Now Playing extrapolates from the elapsed time it was
                    // last given, which is still the end of the song.
                    self.currentTime = 0
                    self.updateNowPlayingInfo()
                }
            }
        } else if currentIndex + 1 >= queue.count {
            _ = pausePlayback()
        } else {
            playNext()
        }
    }

    func toggleMode() {
        let previous = playbackMode
        playbackMode = playbackMode.next
        if sendToPhone(.repeatMode), playbackError != nil { playbackMode = previous }
    }

    func toggleShuffle() {
        let previous = isShuffleOn
        isShuffleOn.toggle()
        if sendToPhone(.shuffle) {
            if playbackError != nil { isShuffleOn = previous }
            return
        }
        if isShuffleOn, let song = currentSong {
            originalQueue = queue
            queue = [song] + queue.filter { $0.id != song.id }.shuffled()
            currentIndex = 0
        } else if !originalQueue.isEmpty {
            queue = originalQueue
            originalQueue = []
            currentIndex = currentSong.flatMap { queue.firstIndex(of: $0) } ?? 0
        }
    }

    func seek(to time: Double) {
        if sendToPhone(.seek, position: time) { return }
        // A live stream has no meaningful position to seek to.
        guard !isRadioMode else { return }
        guard time.isFinite, duration.isFinite, duration > 0 else { return }
        let target = min(max(time, 0), duration)
        currentTime = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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
        startupTimeout?.cancel()
        startupTimeout = nil
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
        // Pause before dropping the player. A detached pause can run after the
        // next player's play call and briefly leave both outputs active.
        if let retired = player {
            player = nil
            retired.pause()
        }
    }

    private func localCacheURL(for songID: String) -> URL {
        let storageKey = SongStorageKey.component(for: songID)
        return AudioManager.audioCacheDir.appendingPathComponent("\(storageKey).mp3")
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

    nonisolated static func acceptsAudioResponse(_ response: URLResponse?) -> Bool {
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

    func clearAllDownloadedAudio(downloads: WatchDownloads = .shared, cacheDirectory: URL? = nil) {
        if WatchAuthManager.shared.output == .watch {
            _ = pausePlayback()
            cleanupPlayer()
            isLoading = false
        }
        downloads.clearStorage()
        clearCache(in: cacheDirectory ?? Self.audioCacheDir)
    }

    static func downloadedAudioSizeBytes(downloads: WatchDownloads = .shared, cacheDirectory: URL? = nil) -> Int64 {
        downloads.storageBytes + cacheSizeBytes(in: cacheDirectory ?? audioCacheDir)
    }

    func clearCache(in directory: URL = AudioManager.audioCacheDir) {
        metadataToken = nil
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
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
            do {
                let loadedDuration = try await asset.load(.duration)
                let isPlayable = try await asset.load(.isPlayable)
                let actual = loadedDuration.seconds
                let durationOK = actual.isFinite && actual > 0
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
            if cacheURL == WatchDownloads.shared.localURL(for: songID) {
                WatchDownloads.shared.invalidate(songID)
                failPlayback("The download is damaged. Connect to the internet and choose Retry Download.")
                return
            }
            try? FileManager.default.removeItem(at: cacheURL)
            noteCacheChanged()
            guard let remoteURL = song.audioURL else {
                failPlayback(String(localized: "This song has no playable audio. Choose another song."))
                return
            }
            setupPlayer(with: remoteURL)
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
        metadataToken = nil
        setupPlayer(with: remoteURL)
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
        @Sendable nonisolated func performOnMain(
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

        let playTarget = cc.playCommand.addTarget { @Sendable [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                guard !self.playbackRequested else { return .commandFailed }
                return self.resumePlayback() ? .success : .commandFailed
            }
        }
        remoteCommandTargets.append((cc.playCommand, playTarget))
        let pauseTarget = cc.pauseCommand.addTarget { @Sendable [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                guard self.playbackRequested else { return .commandFailed }
                return self.pausePlayback() ? .success : .commandFailed
            }
        }
        remoteCommandTargets.append((cc.pauseCommand, pauseTarget))
        let toggleTarget = cc.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                self.togglePlayPause() ? .success : .commandFailed
            }
        }
        remoteCommandTargets.append((cc.togglePlayPauseCommand, toggleTarget))
        let nextTarget = cc.nextTrackCommand.addTarget { @Sendable [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                self.playNext()
                return .success
            }
        }
        remoteCommandTargets.append((cc.nextTrackCommand, nextTarget))
        let previousTarget = cc.previousTrackCommand.addTarget { @Sendable [weak self] _ in
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
        WatchAuthManager.shared.localPlaybackDidChange()
        guard WatchAuthManager.shared.canPlayLocally else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
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
            return Self.makeNowPlayingArtwork(image)
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

    nonisolated static func makeNowPlayingArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    isolated deinit {
        companionProgressTimer?.invalidate()
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
