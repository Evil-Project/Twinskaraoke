import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI

nonisolated enum PlaybackMode {
    case listLoop
    case singleLoop
    var iconName: String {
        switch self {
        case .listLoop: "repeat"
        case .singleLoop: "repeat.1"
        }
    }
}

struct PlayerItemFailureSequence {
    enum Resolution: Equatable {
        case recoverCurrent
        case advance(to: Int)
        case stop
    }

    private var cacheRecoveryAttempts: Set<Int> = []
    private var unrecoverableFailureCount = 0

    mutating func resolve(
        queueCount: Int,
        currentIndex: Int,
        playbackRequested: Bool,
        cacheRecoveryAvailable: Bool
    ) -> Resolution {
        guard playbackRequested, queueCount > 0 else {
            reset()
            return .stop
        }

        let normalizedIndex = min(max(currentIndex, 0), queueCount - 1)
        if cacheRecoveryAvailable,
           cacheRecoveryAttempts.insert(normalizedIndex).inserted
        {
            return .recoverCurrent
        }

        unrecoverableFailureCount += 1
        guard unrecoverableFailureCount < queueCount else { return .stop }
        return .advance(to: (normalizedIndex + 1) % queueCount)
    }

    mutating func reset() {
        cacheRecoveryAttempts.removeAll()
        unrecoverableFailureCount = 0
    }
}

@MainActor
class AudioManager: ObservableObject {
    typealias AudioDownloadLoader = @Sendable (URL) async throws -> (
        temporaryURL: URL,
        responseAccepted: Bool
    )
    typealias AudioValidator = @Sendable (URL, Int) async -> Bool

    static let shared = AudioManager()
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var queue: [Song] = []
    @Published var currentIndex: Int = 0
    @Published var isRadioMode = false
    @Published var playbackMode: PlaybackMode = .listLoop
    @Published var isShuffleOn = false
    @Published var volume: Double = AudioManager.storedVolume()
    private var originalQueue: [Song] = []
    // Song equality is ID-only, so parallel occurrence tokens preserve the
    // exact duplicate selected while the public queue remains `[Song]`.
    private var queueOccurrenceIDs: [UUID] = []
    private var originalQueueOccurrenceIDs: [UUID] = []
    private var currentQueueOccurrenceID: UUID?
    private var player: AVPlayer?
    private let playerObservationLifetime = PlayerObservationLifetime()
    private var lifecycleCancellables = Set<AnyCancellable>()
    private let downloadLoader: AudioDownloadLoader
    private let audioValidator: AudioValidator
    private var downloadTask: Task<Void, Never>?
    private var playbackLoadGeneration: UInt64 = 0
    private var recoveringFromBrokenCache: Set<String> = []
    private var playerItemFailureSequence = PlayerItemFailureSequence()
    private(set) var playbackRequested = false
    private var shouldResumeAfterInterruption = false
    private static let audioCacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let maxCachedFiles = 10
    private static let volumeDefaultsKey = "nk.watchVolume"
    init(
        downloadLoader: @escaping AudioDownloadLoader = AudioManager.loadRemoteAudio,
        audioValidator: @escaping AudioValidator = AudioManager.validateAudioFile
    ) {
        self.downloadLoader = downloadLoader
        self.audioValidator = audioValidator
        setupRemoteCommands()
        setupInterruptionHandler()
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var upNextSongs: [Song] {
        upNextQueueEntries.map(\.song)
    }

    var upNextQueueEntries: [WatchQueueEntry] {
        guard let index = resolvedCurrentQueueIndex else { return [] }
        let nextIndex = index + 1
        guard nextIndex < queue.endIndex else { return [] }
        return queue.indices[nextIndex...].map {
            WatchQueueEntry(queueIndex: $0, song: queue[$0])
        }
    }

    func play(song: Song, context: [Song] = []) {
        isRadioMode = false
        playerItemFailureSequence.reset()
        var playbackQueue = context.isEmpty ? [song] : context
        var selectedIndex = Self.occurrenceIndex(of: song, in: playbackQueue)
        if let selectedIndex {
            playbackQueue[selectedIndex] = song
        } else {
            playbackQueue.insert(song, at: 0)
            selectedIndex = 0
        }

        if isShuffleOn {
            // Picking a song from the current queue keeps the existing
            // shuffled order; a new context is shuffled once with the picked
            // song first, so previous/next walk real play history.
            if Self.queuesMatchByOccurrence(playbackQueue, queue) {
                playbackQueue = queue
                selectedIndex = Self.occurrenceIndex(of: song, in: playbackQueue)
            } else {
                originalQueue = playbackQueue
                originalQueueOccurrenceIDs = playbackQueue.map { _ in UUID() }
                let selection = selectedIndex ?? 0
                var remaining = Array(zip(playbackQueue, originalQueueOccurrenceIDs))
                let selected = remaining.remove(at: selection)
                remaining.shuffle()
                playbackQueue = [selected.0] + remaining.map(\.0)
                queueOccurrenceIDs = [selected.1] + remaining.map(\.1)
                selectedIndex = 0
            }
        } else {
            originalQueue = []
            originalQueueOccurrenceIDs = []
            queueOccurrenceIDs = playbackQueue.map { _ in UUID() }
        }

        if queueOccurrenceIDs.count != playbackQueue.count {
            queueOccurrenceIDs = playbackQueue.map { _ in UUID() }
        }
        queue = playbackQueue
        selectQueueItem(at: selectedIndex ?? 0)
        prepareAndPlay()
    }

    func playRadio(streamURL: URL, song: Song, artworkURL _: URL? = nil) {
        playerItemFailureSequence.reset()
        invalidatePendingLoad()
        cleanupPlayer()
        isRadioMode = true
        currentSong = song
        queue = [song]
        queueOccurrenceIDs = [UUID()]
        currentQueueOccurrenceID = queueOccurrenceIDs.first
        currentIndex = 0
        originalQueue = []
        originalQueueOccurrenceIDs = []
        currentTime = 0
        duration = 0
        playbackRequested = true
        isLoading = true
        isPlaying = false
        setupStreamPlayer(with: streamURL)
    }

    func updateRadioMetadata(song: Song, artworkURL _: URL? = nil) {
        guard isRadioMode else { return }
        currentSong = song
        if queue.isEmpty {
            queue = [song]
            queueOccurrenceIDs = [UUID()]
            currentQueueOccurrenceID = queueOccurrenceIDs.first
            currentIndex = 0
        } else {
            queue[currentIndex] = song
        }
        updateNowPlayingInfo()
    }

    @discardableResult
    func stopRadio() -> Bool {
        guard isRadioMode else { return false }
        invalidatePendingLoad()
        playbackRequested = false
        isPlaying = false
        isLoading = false
        isRadioMode = false
        cleanupPlayer()
        updateNowPlayingInfo()
        return true
    }

    private func prepareAndPlay() {
        cleanupPlayer()
        currentTime = 0
        duration = 0
        isPlaying = false
        playbackRequested = true
        let loadGeneration = invalidatePendingLoad()
        guard let song = currentSong else {
            settleAfterPlayerItemFailure()
            return
        }
        if AppRuntime.isUITestMode {
            duration = Double(max(0, song.duration))
            isLoading = false
            isPlaying = true
            updateNowPlayingInfo()
            return
        }
        let localURL = localCacheURL(for: song.id)
        if FileManager.default.fileExists(atPath: localURL.path) {
            isLoading = true
            validateCacheAndPlay(
                song: song,
                cacheURL: localURL,
                loadGeneration: loadGeneration
            )
            return
        }
        guard let remoteURL = song.audioURL else {
            handlePlaybackFailure()
            return
        }
        isLoading = true
        startDownload(
            from: remoteURL,
            destinationURL: localURL,
            song: song,
            loadGeneration: loadGeneration
        )
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
        playerObservationLifetime.store(
            playerItem.publisher(for: \.duration)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak player] dur in
                    guard let self, let player, self.player === player else { return }
                    let seconds = CMTimeGetSeconds(dur)
                    if !seconds.isNaN, seconds > 0 {
                        duration = seconds
                    }
                }
        )
        playerObservationLifetime.store(
            playerItem.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak player] status in
                    guard let self, let player, self.player === player else { return }
                    if status == .readyToPlay {
                        playerItemFailureSequence.reset()
                        if playbackRequested {
                            player.play()
                        }
                        refreshPlaybackState()
                        updateNowPlayingInfo()
                    } else if status == .failed {
                        handlePlaybackFailure(playbackURL: localURL, failedPlayer: player)
                    }
                }
        )
        playerObservationLifetime.store(
            player.publisher(for: \.timeControlStatus, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak player] _ in
                    guard let self, let player, self.player === player else { return }
                    refreshPlaybackState()
                }
        )
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite, !seconds.isNaN {
                    currentTime = max(0, seconds)
                }
            }
        }
        playerObservationLifetime.replacePeriodicTimeObserver(timeObserver, on: player)
        let endTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playEnded()
            }
        }
        playerObservationLifetime.replacePlaybackEndedObserver(endTimeObserver)
    }

    private func setupStreamPlayer(with streamURL: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, policy: .longFormAudio
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        let playerItem = AVPlayerItem(url: streamURL)
        let player = AVPlayer(playerItem: playerItem)
        player.volume = Float(volume)
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        self.player = player
        playerObservationLifetime.store(
            playerItem.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak player] status in
                    guard let self, let player, self.player === player else { return }
                    if status == .readyToPlay {
                        if playbackRequested {
                            player.play()
                        }
                        refreshPlaybackState()
                        updateNowPlayingInfo()
                    } else if status == .failed {
                        handlePlaybackFailure(failedPlayer: player)
                    }
                }
        )
        playerObservationLifetime.store(
            player.publisher(for: \.timeControlStatus, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak player] _ in
                    guard let self, let player, self.player === player else { return }
                    refreshPlaybackState()
                }
        )
        updateNowPlayingInfo()
        player.play()
    }

    private func handlePlaybackFailure(
        playbackURL: URL? = nil,
        failedPlayer: AVPlayer? = nil
    ) {
        if let failedPlayer, player !== failedPlayer { return }
        isLoading = false
        isPlaying = false

        let queueIndex = resolvedCurrentQueueIndex ?? currentIndex
        var resolution = playerItemFailureSequence.resolve(
            queueCount: queue.count,
            currentIndex: queueIndex,
            playbackRequested: playbackRequested,
            cacheRecoveryAvailable: playbackURL.map {
                canRecoverFromBrokenCache(playbackURL: $0)
            } ?? false
        )

        if resolution == .recoverCurrent, let playbackURL {
            if recoverFromBrokenCache(playbackURL: playbackURL) {
                return
            }
            resolution = playerItemFailureSequence.resolve(
                queueCount: queue.count,
                currentIndex: queueIndex,
                playbackRequested: playbackRequested,
                cacheRecoveryAvailable: false
            )
        }

        switch resolution {
        case .recoverCurrent:
            settleAfterPlayerItemFailure()
        case let .advance(nextIndex):
            guard queue.indices.contains(nextIndex) else {
                settleAfterPlayerItemFailure()
                return
            }
            selectQueueItem(at: nextIndex)
            prepareAndPlay()
        case .stop:
            settleAfterPlayerItemFailure()
        }
    }

    private func settleAfterPlayerItemFailure() {
        playbackRequested = false
        isPlaying = false
        isLoading = false
        isRadioMode = false
        playerItemFailureSequence.reset()
        cleanupPlayer()
        updateNowPlayingInfo()
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
            invalidatePendingLoad()
        }
        guard player != nil || playbackRequested || isLoading else { return false }
        playerItemFailureSequence.reset()
        playbackRequested = false
        player?.pause()
        isPlaying = false
        if isRadioMode {
            return stopRadio()
        }
        if cancelDownload || player != nil {
            isLoading = false
        }
        updateNowPlayingInfo()
        return true
    }

    @discardableResult
    private func resumePlayback() -> Bool {
        playerItemFailureSequence.reset()
        guard let player else {
            if isLoading {
                playbackRequested = true
                updateNowPlayingInfo()
                return true
            }
            // No player and no download in flight (e.g. paused mid-download,
            // which cancels it, or the download failed) — restart from the
            // current song instead of leaving the play button dead.
            if currentSong != nil {
                prepareAndPlay()
                updateNowPlayingInfo()
                return true
            }
            isPlaying = false
            playbackRequested = false
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
        // A direct user/remote action supersedes any automatic resume saved
        // for an interruption. Loading is also an active state: the UI shows
        // a stop control, so tapping it must cancel rather than re-arm playback.
        shouldResumeAfterInterruption = false
        if playbackRequested || isPlaying || isLoading {
            return pausePlayback()
        }
        return resumePlayback()
    }

    func playNext() {
        guard !isRadioMode else { return }
        playerItemFailureSequence.reset()
        guard !queue.isEmpty else { return }
        let index = resolvedCurrentQueueIndex ?? queue.startIndex
        selectQueueItem(at: (index + 1) % queue.count)
        prepareAndPlay()
    }

    func playPrevious() {
        guard !isRadioMode else { return }
        playerItemFailureSequence.reset()
        if currentTime > 3.0 {
            player?.seek(to: .zero)
            return
        }
        guard !queue.isEmpty else {
            player?.seek(to: .zero)
            return
        }
        let index = resolvedCurrentQueueIndex ?? currentIndex
        if index > 0 {
            selectQueueItem(at: index - 1)
            prepareAndPlay()
        } else {
            player?.seek(to: .zero)
        }
    }

    @discardableResult
    func playQueueItem(at index: Int) -> Bool {
        guard queue.indices.contains(index) else { return false }
        playerItemFailureSequence.reset()
        selectQueueItem(at: index)
        prepareAndPlay()
        return true
    }

    func playEnded() {
        playerItemFailureSequence.reset()
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
        playerItemFailureSequence.reset()
        isShuffleOn.toggle()
        if isShuffleOn {
            originalQueue = queue
            if queueOccurrenceIDs.count != queue.count {
                queueOccurrenceIDs = queue.map { _ in UUID() }
            }
            originalQueueOccurrenceIDs = queueOccurrenceIDs
            guard let selectedIndex = resolvedCurrentQueueIndex else { return }
            var remaining = Array(zip(queue, queueOccurrenceIDs))
            let selected = remaining.remove(at: selectedIndex)
            remaining.shuffle()
            queue = [selected.0] + remaining.map(\.0)
            queueOccurrenceIDs = [selected.1] + remaining.map(\.1)
            selectQueueItem(at: 0)
        } else if !originalQueue.isEmpty {
            let selectedOccurrenceID = currentQueueOccurrenceID
            queue = originalQueue
            queueOccurrenceIDs = originalQueueOccurrenceIDs
            originalQueue = []
            originalQueueOccurrenceIDs = []
            let restoredIndex = selectedOccurrenceID.flatMap {
                queueOccurrenceIDs.firstIndex(of: $0)
            }
                ?? Self.occurrenceIndex(of: currentSong, in: queue)
                ?? 0
            selectQueueItem(at: restoredIndex)
        }
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        updateNowPlayingInfo()
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        UserDefaults.standard.set(clamped, forKey: AudioManager.volumeDefaultsKey)
        player?.volume = Float(clamped)
    }

    private static func storedVolume() -> Double {
        guard UserDefaults.standard.object(forKey: volumeDefaultsKey) != nil else { return 1 }
        return min(max(UserDefaults.standard.double(forKey: volumeDefaultsKey), 0), 1)
    }

    private var resolvedCurrentQueueIndex: Int? {
        guard !queue.isEmpty, let currentSong else { return nil }
        if queueOccurrenceIDs.count == queue.count,
           let currentQueueOccurrenceID,
           let occurrenceIndex = queueOccurrenceIDs.firstIndex(of: currentQueueOccurrenceID)
        {
            return occurrenceIndex
        }
        if queue.indices.contains(currentIndex),
           Self.matchesOccurrence(queue[currentIndex], currentSong)
        {
            return currentIndex
        }
        return Self.occurrenceIndex(of: currentSong, in: queue)
    }

    private func cleanupPlayer() {
        playerObservationLifetime.removeAll()
        player?.pause()
        player = nil
    }

    private func selectQueueItem(at index: Int) {
        guard queue.indices.contains(index) else {
            currentIndex = 0
            currentSong = nil
            currentQueueOccurrenceID = nil
            return
        }
        currentIndex = index
        currentSong = queue[index]
        currentQueueOccurrenceID = queueOccurrenceIDs.indices.contains(index)
            ? queueOccurrenceIDs[index]
            : nil
    }

    private nonisolated static func occurrenceIndex(of song: Song?, in queue: [Song]) -> Int? {
        guard let song else { return nil }
        return queue.firstIndex { matchesOccurrence($0, song) }
            ?? queue.firstIndex { $0.id == song.id }
    }

    private nonisolated static func queuesMatchByOccurrence(_ lhs: [Song], _ rhs: [Song]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            matchesOccurrence($0.0, $0.1)
        }
    }

    private nonisolated static func matchesOccurrence(_ lhs: Song, _ rhs: Song) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.duration == rhs.duration
            && lhs.absolutePath == rhs.absolutePath
            && lhs.cloudflareID == rhs.cloudflareID
            && lhs.coverArt?.absolutePath == rhs.coverArt?.absolutePath
            && lhs.coverArt?.cloudflareId == rhs.coverArt?.cloudflareId
            && lhs.originalArtists == rhs.originalArtists
            && lhs.coverArtists == rhs.coverArtists
            && lhs.userUploaded == rhs.userUploaded
            && lhs.oss == rhs.oss
    }

    private func localCacheURL(for songID: String) -> URL {
        AudioManager.audioCacheDir.appendingPathComponent("\(songID).mp3")
    }

    private func finishDownloadedPlayback(
        tempURL: URL,
        responseAccepted: Bool,
        destinationURL: URL,
        song: Song,
        loadGeneration: UInt64
    ) {
        guard playbackLoadGeneration == loadGeneration,
              currentSong?.id == song.id
        else { return }
        guard storeDownloadedAudio(
            tempURL: tempURL,
            responseAccepted: responseAccepted,
            destinationURL: destinationURL
        )
        else {
            handlePlaybackFailure()
            return
        }
        validateCachedFile(at: destinationURL, expectedDuration: song.duration) { [weak self] valid in
            guard let self,
                  playbackLoadGeneration == loadGeneration,
                  currentSong?.id == song.id
            else { return }
            guard valid else {
                try? FileManager.default.removeItem(at: destinationURL)
                handlePlaybackFailure()
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

    nonisolated static func loadRemoteAudio(from url: URL) async throws -> (
        temporaryURL: URL,
        responseAccepted: Bool
    ) {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        return (temporaryURL, acceptsAudioResponse(response))
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
        invalidatePendingLoad()
        if player == nil {
            playbackRequested = false
            isLoading = false
        }
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
        let audioValidator = audioValidator
        Task { @MainActor in
            completion(await audioValidator(url, expectedDuration))
        }
    }

    private nonisolated static func validateAudioFile(
        at url: URL,
        expectedDuration: Int
    ) async -> Bool {
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
            return isPlayable && durationOK
        } catch {
            return false
        }
    }

    private func validateCacheAndPlay(
        song: Song,
        cacheURL: URL,
        loadGeneration: UInt64
    ) {
        let songID = song.id
        validateCachedFile(at: cacheURL, expectedDuration: song.duration) { [weak self] valid in
            guard let self,
                  playbackLoadGeneration == loadGeneration,
                  currentSong?.id == songID
            else { return }
            if valid {
                setupPlayer(with: cacheURL)
                return
            }
            try? FileManager.default.removeItem(at: cacheURL)
            guard let remoteURL = song.audioURL else {
                handlePlaybackFailure()
                return
            }
            startDownload(
                from: remoteURL,
                destinationURL: cacheURL,
                song: song,
                loadGeneration: loadGeneration
            )
        }
    }

    private func canRecoverFromBrokenCache(playbackURL: URL) -> Bool {
        guard playbackURL.path.hasPrefix(AudioManager.audioCacheDir.path),
              let song = currentSong
        else { return false }
        return !recoveringFromBrokenCache.contains(song.id) && song.audioURL != nil
    }

    @discardableResult
    private func recoverFromBrokenCache(playbackURL: URL) -> Bool {
        guard canRecoverFromBrokenCache(playbackURL: playbackURL),
              let song = currentSong,
              let remoteURL = song.audioURL
        else { return false }
        let songID = song.id
        recoveringFromBrokenCache.insert(songID)
        try? FileManager.default.removeItem(at: playbackURL)
        cleanupPlayer()
        isLoading = true
        let loadGeneration = invalidatePendingLoad()
        startDownload(
            from: remoteURL,
            destinationURL: playbackURL,
            song: song,
            loadGeneration: loadGeneration
        )
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.recoveringFromBrokenCache.remove(songID)
        }
        return true
    }

    @discardableResult
    private func invalidatePendingLoad() -> UInt64 {
        playbackLoadGeneration &+= 1
        downloadTask?.cancel()
        downloadTask = nil
        return playbackLoadGeneration
    }

    private func startDownload(
        from remoteURL: URL,
        destinationURL: URL,
        song: Song,
        loadGeneration: UInt64
    ) {
        guard playbackLoadGeneration == loadGeneration else { return }
        let loader = downloadLoader
        let task = Task { @MainActor [weak self] in
            do {
                let result = try await loader(remoteURL)
                guard !Task.isCancelled, let self else {
                    try? FileManager.default.removeItem(at: result.temporaryURL)
                    return
                }
                guard playbackLoadGeneration == loadGeneration,
                      currentSong?.id == song.id
                else {
                    try? FileManager.default.removeItem(at: result.temporaryURL)
                    return
                }
                downloadTask = nil
                finishDownloadedPlayback(
                    tempURL: result.temporaryURL,
                    responseAccepted: result.responseAccepted,
                    destinationURL: destinationURL,
                    song: song,
                    loadGeneration: loadGeneration
                )
            } catch {
                guard !Task.isCancelled,
                      let self,
                      playbackLoadGeneration == loadGeneration,
                      currentSong?.id == song.id
                else { return }
                downloadTask = nil
                handlePlaybackFailure()
            }
        }
        downloadTask = task
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
        cc.playCommand.addTarget { [weak self] _ in
            guard let self, !self.playbackRequested else { return .commandFailed }
            return resumePlayback() ? .success : .commandFailed
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self, playbackRequested else { return .commandFailed }
            return pausePlayback() ? .success : .commandFailed
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return togglePlayPause() ? .success : .commandFailed
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
            .store(in: &lifecycleCancellables)
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
            let shouldResume = shouldResumeAfterInterruption
            // Consume the intent for every ended notification, including
            // malformed ones without an options payload. Otherwise a later,
            // unrelated notification can resume playback unexpectedly.
            shouldResumeAfterInterruption = false
            guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
            if opts.contains(.shouldResume), shouldResume {
                resumePlayback()
            }
        @unknown default:
            shouldResumeAfterInterruption = false
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

    isolated deinit {
        downloadTask?.cancel()
        lifecycleCancellables.removeAll()
        playerObservationLifetime.removeAll()
        player?.pause()
    }
}
