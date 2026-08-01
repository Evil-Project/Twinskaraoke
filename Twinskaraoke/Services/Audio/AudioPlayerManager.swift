import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI

#if canImport(UIKit)
    import SDWebImage
    import UIKit
#endif

/// Tick counter for fade timers; only mutated on the main run loop, but lives
/// in a @Sendable timer closure so it needs an unchecked-Sendable box.
private final class TimerStepCounter: @unchecked Sendable {
    var step = 0
}

enum RepeatMode {
    case off, all, one
    var symbol: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var isActive: Bool {
        self != .off
    }

    func next() -> RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

private enum AudioEffect {
    case karaoke, bassEnhance, vocalEnhance, instrumentalEnhance
}

private enum ManagedAVPlayerKind {
    case radio, stream
}

@MainActor
final class PlaybackClock: ObservableObject {
    static let shared = PlaybackClock()

    @Published var progress: Double = 0

    private init() {}
}

@MainActor
class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var isBuffering = false

    var progress: Double {
        get { PlaybackClock.shared.progress }
        set { PlaybackClock.shared.progress = newValue }
    }

    @Published var queue: [Song] = []
    private(set) var currentQueueIndex: Int?
    @Published var isEditingProgress = false
    @Published var volume: Double = 1.0
    @Published var isUserScrubbingVolume: Bool = false
    private var suppressTransitionAfterSeek = false
    private var preferredStreamResumeSongID: String?
    private var preferredStreamResumeTime: TimeInterval?
    private var deferredAIEffect: AudioEffect?
    @Published var routeIcon: String = "airplayaudio"
    @Published var routeName: String = ""
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffled: Bool = false
    @Published var autoplayEnabled: Bool = true
    @Published var isRadioMode: Bool = false
    @Published var radioArtworkURL: URL?
    private var isStreamMode: Bool {
        streamPlayer != nil
    }

    @Published var aiEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "nk.aiEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "nk.aiEnabled")
        }
        return DeviceCapability.supportsKaraoke
    }() {
        didSet {
            UserDefaults.standard.set(aiEnabled, forKey: "nk.aiEnabled")
            DebugLogger.log("AI enabled: \(aiEnabled)", category: .ai)
            if !aiEnabled {
                _suppressModeSwitch = true
                karaokeMode = false
                bassEnhanceMode = false
                vocalEnhanceMode = false
                instrumentalEnhanceMode = false
                _suppressModeSwitch = false
                preparedStemSongID = nil
                deferredAIEffect = nil
                VocalSeparator.shared.cancel()
                VocalSeparator.shared.cancelBackgroundAnalysis()
                revertAIPlaybackToMain()
                VocalSeparator.shared.cleanupRealtimeTemp()
            }
        }
    }

    @Published var aiAutoAnalyze: Bool = UserDefaults.standard.bool(forKey: "nk.aiAutoAnalyze") {
        didSet {
            UserDefaults.standard.set(aiAutoAnalyze, forKey: "nk.aiAutoAnalyze")
            DebugLogger.log("AI auto-analyze: \(aiAutoAnalyze)", category: .ai)
            if aiAutoAnalyze, aiEnabled, let song = currentSong, !isRadioMode {
                if let effect = currentActiveEffect, !isKaraokePreparedForCurrentSong {
                    deferAIEffectActivation(effect)
                    temporarilyDisableAIEffects()
                }
                triggerBackgroundAnalysis(for: song)
                prepareBackgroundStemPlaybackIfPossible(for: song)
            }
            if !aiAutoAnalyze {
                preparedStemSongID = nil
                deferredAIEffect = nil
                VocalSeparator.shared.cancelBackgroundAnalysis()
                if !anyAIEffectActive {
                    revertAIPlaybackToMain()
                }
            }
        }
    }

    @Published var karaokeMode: Bool = false {
        didSet {
            guard !_suppressModeSwitch else { return }
            if karaokeMode, isBackgroundKaraokeLocked {
                deferAIEffectActivation(.karaoke)
                temporarilyDisableAIEffects()
                return
            }
            if karaokeMode, shouldDeferAIEffectActivation {
                deferAIEffectActivation(.karaoke)
                temporarilyDisableAIEffects()
                return
            }
            if karaokeMode {
                disableOtherModes(except: .karaoke)
            }
            applyMLSeparationIfNeeded()
        }
    }

    @Published var aiVocalStrength: Float = AudioPlayerManager.loadAIVocalStrength() {
        didSet {
            let clamped = min(1, max(0, aiVocalStrength))
            if clamped != aiVocalStrength {
                aiVocalStrength = clamped
                return
            }
            UserDefaults.standard.set(Double(aiVocalStrength), forKey: "nk.aiVocalStrength")
            applyAIMixVolumes()
        }
    }

    private static func loadAIVocalStrength() -> Float {
        let raw = UserDefaults.standard.object(forKey: "nk.aiVocalStrength") as? Double ?? 1.0
        return Float(min(1, max(0, raw)))
    }

    @Published var bassEnhanceMode: Bool = false {
        didSet {
            guard !_suppressModeSwitch else { return }
            if bassEnhanceMode, shouldDeferAIEffectActivation {
                deferAIEffectActivation(.bassEnhance)
                temporarilyDisableAIEffects()
                return
            }
            if bassEnhanceMode {
                disableOtherModes(except: .bassEnhance)
            }
            applyMLSeparationIfNeeded()
        }
    }

    @Published var bassEnhanceStrength: Float = AudioPlayerManager.loadFloat(
        "nk.bassEnhanceStrength", default: 0.5
    ) {
        didSet {
            UserDefaults.standard.set(bassEnhanceStrength, forKey: "nk.bassEnhanceStrength")
            applyAIMixVolumes()
        }
    }

    @Published var vocalEnhanceMode: Bool = false {
        didSet {
            guard !_suppressModeSwitch else { return }
            if vocalEnhanceMode, shouldDeferAIEffectActivation {
                deferAIEffectActivation(.vocalEnhance)
                temporarilyDisableAIEffects()
                return
            }
            if vocalEnhanceMode {
                disableOtherModes(except: .vocalEnhance)
            }
            applyMLSeparationIfNeeded()
        }
    }

    @Published var vocalEnhanceStrength: Float = AudioPlayerManager.loadFloat(
        "nk.vocalEnhanceStrength", default: 0.5
    ) {
        didSet {
            UserDefaults.standard.set(vocalEnhanceStrength, forKey: "nk.vocalEnhanceStrength")
            applyAIMixVolumes()
        }
    }

    @Published var instrumentalEnhanceMode: Bool = false {
        didSet {
            guard !_suppressModeSwitch else { return }
            if instrumentalEnhanceMode, shouldDeferAIEffectActivation {
                deferAIEffectActivation(.instrumentalEnhance)
                temporarilyDisableAIEffects()
                return
            }
            if instrumentalEnhanceMode {
                disableOtherModes(except: .instrumentalEnhance)
            }
            applyMLSeparationIfNeeded()
        }
    }

    @Published var instrumentalEnhanceStrength: Float = AudioPlayerManager.loadFloat(
        "nk.instrumentalEnhanceStrength", default: 0.5
    ) {
        didSet {
            UserDefaults.standard.set(instrumentalEnhanceStrength, forKey: "nk.instrumentalEnhanceStrength")
            applyAIMixVolumes()
        }
    }

    @Published var eqEnabled: Bool = UserDefaults.standard.bool(forKey: "nk.eqEnabled") {
        didSet {
            UserDefaults.standard.set(eqEnabled, forKey: "nk.eqEnabled")
            avEngine.setEQEnabled(eqEnabled)
        }
    }

    private var eqPresetIsApplying = false
    @Published var eqPreset: EQPreset = {
        let raw = UserDefaults.standard.string(forKey: "nk.eqPreset") ?? ""
        return EQPreset(rawValue: raw) ?? .flat
    }() {
        didSet {
            UserDefaults.standard.set(eqPreset.rawValue, forKey: "nk.eqPreset")
            guard eqPreset != .custom else { return }
            eqPresetIsApplying = true
            eqGainsDB = eqPreset.gains
            eqPresetIsApplying = false
        }
    }

    @Published var eqGainsDB: [Float] = (UserDefaults.standard.array(forKey: "nk.eqGainsDB") as? [Float])
        ?? Array(repeating: 0, count: 10)
    {
        didSet {
            UserDefaults.standard.set(eqGainsDB, forKey: "nk.eqGainsDB")
            avEngine.setEQGains(eqGainsDB)
            if !eqPresetIsApplying, eqPreset != .custom, eqGainsDB != eqPreset.gains {
                eqPreset = .custom
            }
        }
    }

    @Published var autoMixEnabled: Bool =
        (UserDefaults.standard.object(forKey: "nk.autoMixEnabled") as? Bool ?? true)
    {
        didSet {
            let changed = autoMixEnabled != oldValue
            UserDefaults.standard.set(autoMixEnabled, forKey: "nk.autoMixEnabled")
            if autoMixEnabled, crossfadeEnabled { crossfadeEnabled = false }
            if changed { cancelPendingTransitionWork() }
            if !autoMixEnabled, !crossfadeEnabled { cancelPendingTransitionWork() }
        }
    }

    @Published var crossfadeEnabled: Bool =
        (UserDefaults.standard.object(forKey: "nk.crossfadeEnabled") as? Bool ?? false)
    {
        didSet {
            let changed = crossfadeEnabled != oldValue
            UserDefaults.standard.set(crossfadeEnabled, forKey: "nk.crossfadeEnabled")
            if crossfadeEnabled, autoMixEnabled { autoMixEnabled = false }
            if changed { cancelPendingTransitionWork() }
            if !crossfadeEnabled, !autoMixEnabled { cancelPendingTransitionWork() }
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
            if crossfadeEnabled, crossfadeSeconds != oldValue {
                cancelPendingTransitionWork()
            }
        }
    }

    @Published var upcomingSong: Song?
    @Published private(set) var preparedStemSongID: String?
    #if canImport(UIKit)
        @Published var nowPlayingArtwork: UIImage?
    #endif
    private var lastNowPlayingElapsedSecond: Int?
    private var lastNowPlayingPlaybackRate: Double?
    private var lastLoggedNowPlayingElapsedSecond: Int?
    private static func loadCrossfadeSeconds() -> Double {
        let raw = UserDefaults.standard.object(forKey: "nk.crossfadeSeconds") as? Double ?? 6.0
        return min(15, max(1, raw))
    }

    private static func loadFloat(_ key: String, default defaultValue: Float) -> Float {
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.float(forKey: key)
        }
        return defaultValue
    }

    private let avEngine = AVEnginePlayback()
    private let transitionCoordinator = TransitionCoordinator()
    private var radioPlayer: AVPlayer?
    private var streamPlayer: AVPlayer?
    private var streamEndObserver: NSObjectProtocol?
    private var radioTimeObserver: (player: AVPlayer, token: Any)?
    private var radioPlayerCancellables = Set<AnyCancellable>()
    private var streamPlayerCancellables = Set<AnyCancellable>()
    private var radioPlaybackRequested = false
    private var streamPlaybackRequested = false
    private var remotePlaybackCacheTask: Task<Void, Never>?
    private var remotePlaybackCacheToken: UUID?
    private var autoplayFetchTask: Task<Void, Never>?
    private var autoplayFetchOwnership = LatestLoadOwnershipGate()
    private var lastKnownPlaybackTime: TimeInterval = 0
    private var pollTimer: Timer?
    private var streamFadeTimer: Timer?
    private var streamStartedAt: Date?

    private var _suppressModeSwitch = false
    private var originalQueue: [Song] = []
    private var queueOccurrenceTokens: [UUID] = []
    private var originalQueueOccurrenceTokens: [UUID] = []
    private var currentQueueOccurrenceToken: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var artworkURL: URL?
    private var artworkTask: (any SDWebImageOperation)?
    private var artworkProcessingTask: Task<Void, Never>?
    private var playerArtworkWarmupTasks: [String: any SDWebImageOperation] = [:]
    private var warmedPlayerArtworkAt: [String: Date] = [:]
    private var currentPlaybackURL: URL?
    private var instrumentalTask: Task<Void, Never>?
    private var backgroundAnalysisRetryTask: Task<Void, Never>?
    private var backgroundAnalysisRetryGeneration: UInt64 = 0
    private var cacheCompressionTask: Task<Void, Never>?
    private var aiStemSwitchInFlightSongID: String?
    private var quickCutTimer: Timer?
    private var quickCutFallbackTask: Task<Void, Never>?
    private var quickCutCompletionGate = TransitionRampCompletionGate()
    private var separationGeneration: UInt64 = 0
    private var transitionTimeoutGeneration: UInt64 = 0
    private var activeCrossfadePlan: TransitionCoordinator.TransitionPlan?
    private var suppressPlaybackEndedUntil: Date = .distantPast
    private var wasPlayingBeforeInterruption = false
    private var handlingAudioSessionInterruption = false

    private let easterEggSongID = "73376790-47d2-4c17-a7fc-88d11dccd2f0"
    private var easterEggQueuedForCurrentSong = false
    private var easterEggLyricsTask: Task<Void, Never>?
    private var easterEggSongTask: Task<Void, Never>?

    #if canImport(UIKit)
        private var trackTransitionTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    static let audioCacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    #if canImport(UIKit)
        // nonisolated(unsafe): NSCache is documented thread-safe; the artwork
        // processing task reads and writes it off the main actor.
        private nonisolated(unsafe) static let artworkCache: NSCache<NSURL, UIImage> = {
            let cache = NSCache<NSURL, UIImage>()
            cache.countLimit = 32
            cache.totalCostLimit = 32 * 1024 * 1024
            return cache
        }()

        private nonisolated static let artworkMaxPixel: CGFloat = 600
    #endif

    var anyAIEffectActive: Bool {
        karaokeMode || bassEnhanceMode || vocalEnhanceMode || instrumentalEnhanceMode
    }

    private var shouldDeferAIEffectActivation: Bool {
        guard aiEnabled, aiAutoAnalyze, !isRadioMode else { return false }
        guard currentSong != nil else { return false }
        return !isKaraokePreparedForCurrentSong
    }

    private var isRemotePlaybackCaching: Bool {
        remotePlaybackCacheTask != nil
    }

    private var isPlaybackRequested: Bool {
        if isRadioMode { return radioPlaybackRequested }
        if isRemotePlaybackCaching { return streamPlaybackRequested }
        if isStreamMode { return streamPlaybackRequested }
        return isPlaying
    }

    private var nowPlayingPlaybackRate: Double {
        isPlaybackRequested ? 1.0 : 0.0
    }

    var isBackgroundKaraokeLocked: Bool {
        guard aiEnabled, aiAutoAnalyze, !isRadioMode else { return false }
        guard currentSong != nil else { return false }
        return !isKaraokePreparedForCurrentSong
    }

    var isKaraokePreparedForCurrentSong: Bool {
        guard let songID = currentSong?.id else { return false }
        return preparedStemSongID == songID
    }

    private func setPlaybackState(
        playing: Bool,
        buffering: Bool,
        reloadArtwork: Bool = false,
        forceNowPlayingUpdate: Bool = false,
        reason: String = #function
    ) {
        let changed = isPlaying != playing || isBuffering != buffering || reloadArtwork
        isPlaying = playing
        isBuffering = buffering
        if changed {
            DebugLogger.log(
                "Playback state changed: playing=\(playing), buffering=\(buffering), reason=\(reason)",
                category: .playback
            )
        }
        if changed || forceNowPlayingUpdate {
            updateNowPlayingInfo(reloadArtwork: reloadArtwork)
        }
    }

    init() {
        configureAudioSessionCategory()
        activateAudioSession()
        AudioPlayerManager.cleanupOrphanPartialCacheFiles()
        DebugLogger.log("AudioPlayerManager initializing", category: .playback)
        setupRemoteCommands()

        avEngine.onPlaybackEnded = { [weak self] in
            guard let self, !self.isRadioMode else { return }
            guard isPlaying else { return }
            guard !avEngine.isCrossfading, !avEngine.isCrossfadePending else { return }
            guard quickCutTimer == nil else { return }
            // finalizeCrossfade stops the outgoing player, which fires its
            // scheduled completion while the handoff is still settling; the
            // engine flags above are already cleared then, so treating it as
            // a real track end would restart the incoming song from zero.
            // The coordinator owns advancing until the plan is cleared.
            guard !transitionCoordinator.state.isCrossfading, activeCrossfadePlan == nil else {
                DebugLogger.log(
                    "Ignoring playback-ended during transition handoff",
                    category: .playback
                )
                return
            }
            guard !suppressTransitionAfterSeek else { return }
            guard !isPlaybackEndedCallbackSuppressed else {
                DebugLogger.log("Ignoring suppressed playback-ended callback", category: .playback)
                return
            }
            if handlePrematurePlaybackEndIfNeeded(source: "AVEngine") { return }
            playNextOrRandom()
        }
        avEngine.onCrossfadeCompleted = { [weak self] in
            guard let self else { return }
            transitionCoordinatorDidFinish()
        }
        avEngine.onCrossfadeStarted = { [weak self] in
            guard let self, isStreamMode, !self.isRadioMode else { return }
            guard case let .crossfading(plan) = transitionCoordinator.state else { return }
            fadeOutStreamPlayer(duration: plan.fadeDuration)
        }
        avEngine.onPlaybackError = { [weak self] error in
            guard let self else { return }
            DebugLogger.log("AVEngine playback error: \(error)", category: .playback)
            let failedStemSwitchSongID = aiStemSwitchInFlightSongID
            aiStemSwitchInFlightSongID = nil
            let pendingTransitionPlan: TransitionCoordinator.TransitionPlan? = if case let .crossfading(plan) = transitionCoordinator.state {
                plan
            } else {
                nil
            }
            cancelPendingTransitionWork()
            if let pendingTransitionPlan, !self.isRadioMode {
                DebugLogger.log(
                    "Recovering from transition playback error with direct play(\(pendingTransitionPlan.nextSong.id))",
                    category: .playback
                )
                play(
                    song: pendingTransitionPlan.nextSong,
                    queueIndex: pendingTransitionPlan.nextQueueIndex,
                    resetTransitionVolume: true
                )
                return
            }
            if let song = currentSong, !self.isRadioMode,
               failedStemSwitchSongID == song.id || avEngine.mode == .aiStems
            {
                DebugLogger.log(
                    "Removing broken AI stem cache and falling back to main playback for \(song.id)",
                    category: .cache
                )
                AudioCacheStore.removeStemCache(for: song.id)
                preparedStemSongID = nil
                deferredAIEffect = nil
                _suppressModeSwitch = true
                karaokeMode = false
                bassEnhanceMode = false
                vocalEnhanceMode = false
                instrumentalEnhanceMode = false
                _suppressModeSwitch = false
                fallBackToMainPlayback(for: song, startAt: lastKnownPlaybackTime)
                return
            }
            if let song = currentSong, !self.isRadioMode,
               let playbackURL = currentPlaybackURL,
               playbackURL.path.hasPrefix(AudioPlayerManager.audioCacheDir.path)
            {
                DebugLogger.log(
                    "Removing broken cache and retrying from remote for \(song.id)",
                    category: .cache
                )
                AudioCacheStore.removeSongCache(for: song.id)
                currentPlaybackURL = nil
                play(song: song)
                return
            }
            setPlaybackState(
                playing: false,
                buffering: false,
                reason: "avEngine.onPlaybackEnded"
            )
        }
        avEngine.onEngineConfigurationChange = { [weak self] in
            self?.recoverFromEngineConfigChange()
        }
        avEngine.setEQEnabled(eqEnabled)
        avEngine.setEQGains(eqGainsDB)
        startPollTimer()

        transitionCoordinator.avEngine = avEngine
        transitionCoordinator.onBeginTransition = { [weak self] plan in
            self?.handleTransitionBegin(plan: plan)
        }
        transitionCoordinator.onUpcomingSongDetermined = { [weak self] song in
            self?.upcomingSong = song
        }

        FallbackArtProvider.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] note in self?.handleInterruption(note) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] note in self?.handleRouteChange(note) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .vocalSeparatorDidCacheStems)
            .sink { [weak self] note in
                guard let self, let songID = note.object as? String else { return }
                handleCachedStemsReady(songID: songID)
            }
            .store(in: &cancellables)
        updateRouteIcon()
        AVAudioSession.sharedInstance().publisher(for: \.outputVolume)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sysVol in
                guard let self else { return }
                guard !isUserScrubbingVolume else { return }
                let v = Double(sysVol)
                if abs(volume - v) > 0.01 { volume = v }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in self?.handleMediaServicesReset() }
            .store(in: &cancellables)
        #if canImport(UIKit)
            NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
                .sink { [weak self] _ in self?.handleMemoryWarning() }
                .store(in: &cancellables)
        #endif
    }

    deinit {
        // AudioPlayerManager is a main-actor singleton; if it is ever torn
        // down, the last reference is released on the main thread.
        MainActor.assumeIsolated {
            pollTimer?.invalidate()
            quickCutTimer?.invalidate()
            quickCutFallbackTask?.cancel()
            streamFadeTimer?.invalidate()
            instrumentalTask?.cancel()
            backgroundAnalysisRetryTask?.cancel()
            remotePlaybackCacheTask?.cancel()
            autoplayFetchTask?.cancel()
            easterEggLyricsTask?.cancel()
            easterEggSongTask?.cancel()
            if let existing = radioTimeObserver {
                existing.player.removeTimeObserver(existing.token)
            }
            artworkTask?.cancel()
            artworkProcessingTask?.cancel()
            playerArtworkWarmupTasks.values.forEach { $0.cancel() }
            playerArtworkWarmupTasks.removeAll()
            cacheCompressionTask?.cancel()
            radioPlayer?.pause()
            #if canImport(UIKit)
                let transitionTaskID = trackTransitionTaskID
                trackTransitionTaskID = .invalid
                if transitionTaskID != .invalid {
                    Task { @MainActor in
                        UIApplication.shared.endBackgroundTask(transitionTaskID)
                    }
                }
            #endif
        }
    }

    private func cancelBackgroundAnalysisRetry() {
        backgroundAnalysisRetryGeneration &+= 1
        backgroundAnalysisRetryTask?.cancel()
        backgroundAnalysisRetryTask = nil
    }

    private func cancelPendingAutoplayFetch() {
        let cancelledLoad = autoplayFetchOwnership.cancel()
        autoplayFetchTask?.cancel()
        autoplayFetchTask = nil
        #if canImport(UIKit)
            if cancelledLoad != nil {
                endTrackTransitionBackgroundTask()
            }
        #endif
    }

    private func localPlaybackFileURL(for song: Song) -> URL? {
        if let downloaded = DownloadManager.shared.playableURL(for: song) {
            return downloaded
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        return AudioCacheStore.playableMainURL(for: song.id, expectedRemoteURL: song.audioURL, expectedDuration: expectedDuration)
    }

    /// Local file lookup for the tap-to-play path: never decompresses on the
    /// main thread. Compressed-only cache entries return nil here and are
    /// recovered off-main by the remote playback cache task (which hits the
    /// same cache and decompresses before playing, without re-downloading).
    private func immediateLocalPlaybackFileURL(for song: Song) -> URL? {
        if let downloaded = DownloadManager.shared.playableURL(for: song) {
            return downloaded
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        return AudioCacheStore.immediatelyPlayableMainURL(
            for: song.id,
            expectedRemoteURL: song.audioURL,
            expectedDuration: expectedDuration
        )
    }

    private func cachedStems(for song: Song, sourceURL: URL? = nil) -> CachedStems? {
        let expectedDuration: TimeInterval?
        if song.duration > 0 {
            expectedDuration = TimeInterval(song.duration)
        } else if let sourceURL {
            let duration = AudioCacheStore.audioDuration(at: sourceURL)
            expectedDuration = duration.isFinite && duration > 1.0 ? duration : nil
        } else {
            expectedDuration = nil
        }
        return VocalSeparator.shared.cachedStems(
            forSongID: song.id,
            expectedDuration: expectedDuration
        )
    }

    private func activeSongIDs() -> Set<String> {
        var ids = Set<String>()
        if let id = currentSong?.id { ids.insert(id) }
        if let id = upcomingSong?.id { ids.insert(id) }
        if let current = currentSong,
           let next = QueueOccurrenceNavigator.nextSelection(
               currentSong: current,
               currentIndex: currentQueueIndex,
               queue: queue,
               wrapsAtEnd: repeatMode == .all
           )
        {
            ids.insert(next.song.id)
        }
        return ids
    }

    private func setPreferredStreamResumeTime(_ seconds: TimeInterval, for songID: String?) {
        guard let songID, seconds.isFinite else { return }
        preferredStreamResumeSongID = songID
        preferredStreamResumeTime = max(0, seconds)
    }

    private func clearPreferredStreamResumeTime() {
        preferredStreamResumeSongID = nil
        preferredStreamResumeTime = nil
    }

    private func preferredStreamResumeTime(for song: Song? = nil) -> TimeInterval? {
        let songID = song?.id ?? currentSong?.id
        guard preferredStreamResumeSongID == songID else { return nil }
        return preferredStreamResumeTime
    }

    private func reconcilePreferredStreamResumeTime(
        observedTime: TimeInterval,
        for song: Song? = nil
    ) {
        guard let target = preferredStreamResumeTime(for: song) else { return }
        guard observedTime.isFinite, observedTime >= 0 else { return }
        if abs(observedTime - target) <= 2.0 {
            clearPreferredStreamResumeTime()
        }
    }

    private func activePlaybackTime(for song: Song? = nil) -> TimeInterval {
        if !isPlaying, !isBuffering, lastKnownPlaybackTime.isFinite, lastKnownPlaybackTime >= 0 {
            return lastKnownPlaybackTime
        }
        if isStreamMode {
            let fallbackDuration = Double(song?.duration ?? currentSong?.duration ?? 0)
            if let preferredResume = preferredStreamResumeTime(for: song) {
                if fallbackDuration > 0 {
                    return min(max(0, preferredResume), fallbackDuration)
                }
                return max(0, preferredResume)
            }
            if suppressTransitionAfterSeek, fallbackDuration > 0 {
                return min(max(0, progress * fallbackDuration), fallbackDuration)
            }
            let streamTime = streamPlayer?.currentTime().seconds ?? .nan
            if streamTime.isFinite, streamTime >= 0 {
                return streamTime
            }
            if fallbackDuration > 0 {
                return progress * fallbackDuration
            }
            return 0
        }
        if isRemotePlaybackCaching, let preferredResume = preferredStreamResumeTime(for: song) {
            let fallbackDuration = Double(song?.duration ?? currentSong?.duration ?? 0)
            if fallbackDuration > 0 {
                return min(max(0, preferredResume), fallbackDuration)
            }
            return max(0, preferredResume)
        }
        let currentTime = avEngine.currentTime
        if currentTime.isFinite, currentTime >= 0 {
            return currentTime
        }
        return 0
    }

    var playbackTime: TimeInterval {
        activePlaybackTime()
    }

    var playbackDuration: TimeInterval {
        if isStreamMode {
            let streamDuration = streamPlayer?.currentItem?.duration.seconds ?? .nan
            if streamDuration.isFinite, streamDuration > 0 {
                return streamDuration
            }
        }
        if avEngine.currentURL != nil {
            let audioDuration = avEngine.duration
            if audioDuration.isFinite, audioDuration > 0 {
                return audioDuration
            }
        }
        if let song = currentSong, song.duration > 0 {
            return Double(song.duration)
        }
        return 0
    }

    private var isPlaybackEndedCallbackSuppressed: Bool {
        Date() < suppressPlaybackEndedUntil
    }

    private func suppressPlaybackEndedCallbacks(for seconds: TimeInterval = 1.0) {
        suppressPlaybackEndedUntil = Date().addingTimeInterval(seconds)
    }

    private func playbackSourceDescription(_ url: URL?) -> String {
        guard let url else { return "none" }
        if url.isFileURL {
            if url.path.hasPrefix(AudioPlayerManager.audioCacheDir.path) {
                return url.pathExtension == "partial"
                    ? "audio-cache-partial/\(url.lastPathComponent)"
                    : "audio-cache/\(url.lastPathComponent)"
            }
            return "file/\(url.lastPathComponent)"
        }
        let host = url.host ?? "unknown-host"
        let fileName = url.lastPathComponent.isEmpty ? "stream" : url.lastPathComponent
        return "remote/\(host)/\(fileName)"
    }

    private func streamItemDiagnostics() -> String {
        guard let player = streamPlayer, let item = player.currentItem else { return "stream=none" }
        let duration = item.duration.seconds
        let durationText = duration.isFinite ? String(format: "%.2f", duration) : "unknown"
        let loadedRanges = item.loadedTimeRanges
            .map(\.timeRangeValue)
            .map { range -> String in
                let start = range.start.seconds
                let end = CMTimeAdd(range.start, range.duration).seconds
                guard start.isFinite, end.isFinite else { return "unknown" }
                return String(format: "%.2f-%.2f", start, end)
            }
            .joined(separator: ",")
        let status = switch item.status {
        case .unknown: "unknown"
        case .readyToPlay: "ready"
        case .failed: "failed"
        @unknown default: "unknown-default"
        }
        let itemError = item.error?.localizedDescription ?? "none"
        let playerError = player.error?.localizedDescription ?? "none"
        return "streamDuration=\(durationText), loaded=[\(loadedRanges)], itemStatus=\(status), itemError=\(itemError), playerError=\(playerError)"
    }

    private func handlePrematurePlaybackEndIfNeeded(source: String) -> Bool {
        guard let song = currentSong, !isRadioMode else { return false }
        let expectedDuration = TimeInterval(song.duration)
        guard expectedDuration.isFinite, expectedDuration > 15 else { return false }
        let elapsed = activePlaybackTime(for: song)
        guard elapsed.isFinite else { return false }
        let minimumExpectedElapsed = min(8.0, max(3.0, expectedDuration * 0.08))
        guard elapsed < minimumExpectedElapsed else { return false }

        DebugLogger.log(
            "Ignoring premature playback end from \(source) for \(song.id): elapsed=\(elapsed), expected=\(expectedDuration), source=\(playbackSourceDescription(currentPlaybackURL)), \(streamItemDiagnostics())",
            category: .playback
        )
        suppressPlaybackEndedCallbacks(for: 2.0)

        if let playbackURL = currentPlaybackURL,
           playbackURL.path.hasPrefix(AudioPlayerManager.audioCacheDir.path)
        {
            DebugLogger.log(
                "Removing suspect cached audio after premature end for \(song.id)",
                category: .cache
            )
            AudioCacheStore.removeSongCache(for: song.id)
            currentPlaybackURL = nil
        } else if let playbackURL = currentPlaybackURL,
                  playbackURL.isFileURL,
                  DownloadManager.shared.isDownloaded(song.id)
        {
            if DownloadManager.shared.repairIfDownloadedFileIsBroken(for: song) {
                currentPlaybackURL = nil
            } else {
                DebugLogger.log(
                    "Ignoring stale premature-end callback for valid download \(song.id)",
                    category: .playback
                )
                return true
            }
        }

        if let remoteURL = song.audioURL {
            avEngine.stop()
            let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
            startStreamPlayback(
                url: remoteURL,
                songID: song.id,
                expectedDuration: expectedDuration,
                startAt: max(0, elapsed),
                autoplay: isPlaybackRequested
            )
        } else {
            setPlaybackState(
                playing: false,
                buffering: false,
                reason: "prematureEnd.noRemoteFallback"
            )
        }
        return true
    }

    private func keepPreparedStems(for song: Song? = nil) -> Bool {
        guard aiEnabled, aiAutoAnalyze, !isRadioMode else { return false }
        let targetID = song?.id ?? currentSong?.id
        return preparedStemSongID == targetID
    }

    private func isAIStemPlaybackRequested(for songID: String) -> Bool {
        aiEnabled && !isRadioMode && currentSong?.id == songID && anyAIEffectActive
    }

    private func handleAIStemLoadCancellation(for songID: String) {
        guard aiStemSwitchInFlightSongID == songID else { return }
        aiStemSwitchInFlightSongID = nil
        #if canImport(UIKit)
            endTrackTransitionBackgroundTask()
        #endif
    }

    private func revertAIPlaybackToMain() {
        avEngine.revertToMain()
        aiStemSwitchInFlightSongID = nil
    }

    private func handleCachedStemsReady(songID: String) {
        guard currentSong?.id == songID else { return }
        guard aiEnabled, aiAutoAnalyze, !isRadioMode else { return }
        if let song = currentSong {
            prepareBackgroundStemPlaybackIfPossible(for: song)
        }
        restoreDeferredAIEffectIfNeeded(for: songID)
    }

    private func deferAIEffectActivation(_ effect: AudioEffect) {
        deferredAIEffect = effect
        if let song = currentSong, aiEnabled, aiAutoAnalyze, !isRadioMode {
            triggerBackgroundAnalysis(for: song)
        }
    }

    private func temporarilyDisableAIEffects() {
        _suppressModeSwitch = true
        karaokeMode = false
        bassEnhanceMode = false
        vocalEnhanceMode = false
        instrumentalEnhanceMode = false
        _suppressModeSwitch = false
        revertAIPlaybackToMain()
    }

    private func restoreDeferredAIEffectIfNeeded(
        for songID: String,
        applyImmediately: Bool = true
    ) {
        guard currentSong?.id == songID else { return }
        guard aiEnabled, aiAutoAnalyze, !isRadioMode, isKaraokePreparedForCurrentSong else { return }
        guard let effect = deferredAIEffect else { return }
        deferredAIEffect = nil
        _suppressModeSwitch = true
        switch effect {
        case .karaoke:
            karaokeMode = true
        case .bassEnhance:
            bassEnhanceMode = true
        case .vocalEnhance:
            vocalEnhanceMode = true
        case .instrumentalEnhance:
            instrumentalEnhanceMode = true
        }
        _suppressModeSwitch = false
        if applyImmediately {
            applyMLSeparationIfNeeded()
        }
    }

    private func prepareBackgroundStemPlaybackIfPossible(for song: Song) {
        guard aiEnabled, aiAutoAnalyze, !isRadioMode else { return }
        guard let sourceURL = localPlaybackFileURL(for: song) else { return }
        guard let stems = cachedStems(for: song, sourceURL: sourceURL) else { return }

        preparedStemSongID = song.id
        guard anyAIEffectActive else { return }
        switchActivePlaybackToStems(
            for: song, stems: stems, sourceURL: sourceURL,
            onReady: { [weak self] in self?.applyAIMixVolumes() }
        )
    }

    private func scheduleIdleCacheCompression(excluding songIDs: Set<String>) {
        cacheCompressionTask?.cancel()
        cacheCompressionTask = Task.detached(priority: .utility) {
            AudioCacheStore.compressIdleAssets(excluding: songIDs)
            await MainActor.run {
                CacheManager.shared.refreshSizes()
            }
        }
    }

    private func switchActivePlaybackToStems(
        for song: Song, stems: CachedStems, sourceURL: URL,
        onReady: (() -> Void)? = nil
    ) {
        guard !isRadioMode else {
            stems.temporaryLease?.cleanup()
            return
        }
        suppressPlaybackEndedCallbacks()
        let shouldResume = isPlaybackRequested
        let startAt = activePlaybackTime(for: song)
        currentPlaybackURL = sourceURL
        configureAudioSessionCategory()
        activateAudioSession()
        if shouldResume {
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        }
        let readyBlock: () -> Void = { [weak self] in
            guard let self else { return }
            if aiStemSwitchInFlightSongID == song.id {
                aiStemSwitchInFlightSongID = nil
            }
            onReady?()
            #if canImport(UIKit)
                endTrackTransitionBackgroundTask()
            #endif
        }
        let shouldPlay: @MainActor () -> Bool = { [weak self] in
            self?.isPlaybackRequested == true
        }
        let isRequestValid: @MainActor () -> Bool = { [weak self] in
            self?.isAIStemPlaybackRequested(for: song.id) == true
        }
        let onCancelled: @MainActor () -> Void = { [weak self] in
            self?.handleAIStemLoadCancellation(for: song.id)
        }
        if isStreamMode {
            stopStreamPlayer()
            avEngine.playStems(
                originalURL: sourceURL,
                vocalsURL: stems.vocals,
                instrumentsURL: stems.instruments,
                startOffset: stems.startOffset,
                startAt: startAt,
                temporaryLease: stems.temporaryLease,
                shouldPlay: shouldPlay,
                isRequestValid: isRequestValid,
                onCancelled: onCancelled,
                onReady: readyBlock
            )
        } else {
            avEngine.switchToStems(
                vocalsURL: stems.vocals,
                instrumentsURL: stems.instruments,
                startOffset: stems.startOffset,
                temporaryLease: stems.temporaryLease,
                shouldPlay: shouldPlay,
                isRequestValid: isRequestValid,
                onCancelled: onCancelled,
                onReady: readyBlock
            )
        }
        aiStemSwitchInFlightSongID = song.id
        setPlaybackState(
            playing: shouldResume,
            buffering: false,
            reason: "switchToPreparedStems"
        )
    }

    private func cancelQuickCutTimer(resetVolume: Bool = true) {
        quickCutTimer?.invalidate()
        quickCutTimer = nil
        quickCutFallbackTask?.cancel()
        quickCutFallbackTask = nil
        quickCutCompletionGate.invalidate()
        if resetVolume {
            avEngine.setMasterVolume(1.0)
        }
    }

    private func cancelPendingTransitionWork(resetVolume: Bool = true) {
        cancelPendingAutoplayFetch()
        transitionTimeoutGeneration &+= 1
        activeCrossfadePlan = nil
        cancelQuickCutTimer(resetVolume: resetVolume)
        avEngine.cancelCrossfade()
        streamFadeTimer?.invalidate()
        streamFadeTimer = nil
        if resetVolume { streamPlayer?.volume = 1.0 }
        transitionCoordinator.reset()
        upcomingSong = nil
        cancelBackgroundAnalysisRetry()
        #if canImport(UIKit)
            endTrackTransitionBackgroundTask()
        #endif
    }

    private func handleMemoryWarning() {
        DebugLogger.log(
            "Memory warning received — cancelling AI work and reclaiming caches",
            category: .playback
        )
        cancelPendingTransitionWork()
        cancelPlayerArtworkWarmups()
        instrumentalTask?.cancel()
        instrumentalTask = nil
        resetEasterEggWork()
        cancelBackgroundAnalysisRetry()
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        preparedStemSongID = nil
        if anyAIEffectActive {
            _suppressModeSwitch = true
            karaokeMode = false
            bassEnhanceMode = false
            vocalEnhanceMode = false
            instrumentalEnhanceMode = false
            _suppressModeSwitch = false
        }
        revertAIPlaybackToMain()
        VocalSeparator.shared.cleanupRealtimeTemp()
        #if canImport(UIKit)
            AudioPlayerManager.artworkCache.removeAllObjects()
            nowPlayingArtwork = nil
        #endif
        URLCache.shared.removeAllCachedResponses()
        CacheManager.shared.refreshSizes()
        updateNowPlayingInfo(reloadArtwork: false)
    }

    private func disableOtherModes(except keep: AudioEffect) {
        _suppressModeSwitch = true
        if keep != .karaoke { karaokeMode = false }
        if keep != .bassEnhance { bassEnhanceMode = false }
        if keep != .vocalEnhance { vocalEnhanceMode = false }
        if keep != .instrumentalEnhance { instrumentalEnhanceMode = false }
        _suppressModeSwitch = false
    }

    private var currentActiveEffect: AudioEffect? {
        if karaokeMode { return .karaoke }
        if bassEnhanceMode { return .bassEnhance }
        if vocalEnhanceMode { return .vocalEnhance }
        if instrumentalEnhanceMode { return .instrumentalEnhance }
        return nil
    }

    private func applyAIMixVolumes() {
        guard avEngine.mode == .aiStems else { return }
        avEngine.resetInstrumentalEQ()
        if karaokeMode {
            avEngine.setAIMix(main: 0, vocals: max(0, 1.0 - aiVocalStrength), instrumental: 1)
        } else if bassEnhanceMode {
            avEngine.setAIMix(main: 0, vocals: 1, instrumental: 1)
            avEngine.setInstrumentalEQGain(dB: 12.0 * bassEnhanceStrength)
        } else if vocalEnhanceMode {
            avEngine.setAIMix(main: 0, vocals: 1 + 0.5 * vocalEnhanceStrength, instrumental: 1)
        } else if instrumentalEnhanceMode {
            avEngine.setAIMix(main: 0, vocals: 1, instrumental: 1 + 0.5 * instrumentalEnhanceStrength)
        } else {
            avEngine.setAIMix(main: 1, vocals: 0, instrumental: 0)
        }
    }

    private func startPollTimer() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !self.isRadioMode else { return }
                guard !self.isEditingProgress else { return }
                guard self.currentSong != nil else { return }
                if self.suppressTransitionAfterSeek {
                    self.suppressTransitionAfterSeek = false
                    return
                }
                guard self.isPlaying else {
                    if case .idle = self.transitionCoordinator.state {} else {
                        self.transitionCoordinator.reset()
                    }
                    return
                }
                if self.isStreamMode {
                    guard let player = self.streamPlayer,
                          let item = player.currentItem,
                          item.status == .readyToPlay else { return }
                    let t = player.currentTime().seconds
                    self.lastKnownPlaybackTime = t
                    self.reconcilePreferredStreamResumeTime(observedTime: t, for: self.currentSong)
                    let itemDuration = item.duration.seconds
                    let dur = (itemDuration.isFinite && itemDuration > 0) ? itemDuration : self.playbackDuration
                    guard dur.isFinite, dur > 0 else { return }
                    let newProgress = min(1.0, max(0.0, t / dur))
                    if abs(newProgress - self.progress) > 0.0005 {
                        self.advanceProgressTick(to: newProgress)
                    }
                    self.updateNowPlayingElapsed(t)

                    if self.repeatMode != .one {
                        self.transitionCoordinator.poll(
                            currentTime: t,
                            totalDuration: dur,
                            currentSong: self.currentSong,
                            currentQueueIndex: self.currentQueueIndex,
                            queue: self.queue,
                            repeatMode: self.repeatMode,
                            autoMixEnabled: self.autoMixEnabled,
                            crossfadeEnabled: self.crossfadeEnabled,
                            crossfadeSeconds: self.crossfadeSeconds,
                            aiEffectActive: self.anyAIEffectActive
                        )
                    }
                    return
                }
                if !self.avEngine.isEngineRunning {
                    DebugLogger.log("Poll detected engine stopped — recovering", category: .playback)
                    self.recoverFromEngineConfigChange()
                    return
                }
                let totalDur = self.playbackDuration
                guard totalDur.isFinite, totalDur > 0 else { return }
                let t = min(max(0, self.avEngine.currentTime), totalDur)
                self.lastKnownPlaybackTime = t
                let newProgress = min(1.0, max(0.0, t / totalDur))
                if abs(newProgress - self.progress) > 0.0005 {
                    self.advanceProgressTick(to: newProgress)
                }
                self.updateNowPlayingElapsed(t)

                if self.repeatMode != .one {
                    self.transitionCoordinator.poll(
                        currentTime: t,
                        totalDuration: totalDur,
                        currentSong: self.currentSong,
                        currentQueueIndex: self.currentQueueIndex,
                        queue: self.queue,
                        repeatMode: self.repeatMode,
                        autoMixEnabled: self.autoMixEnabled,
                        crossfadeEnabled: self.crossfadeEnabled,
                        crossfadeSeconds: self.crossfadeSeconds,
                        aiEffectActive: self.anyAIEffectActive
                    )
                }
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Publishes a poll-timer progress tick inside a linear animation matching
    /// the poll cadence, so progress UI glides between the 0.25s samples
    /// instead of stepping four times per second. Seeks and track changes
    /// assign `progress` directly and stay instant; large or backward deltas
    /// (stream rebuffers, repeat-one wraps) also snap so the bar never sweeps.
    private func advanceProgressTick(to newProgress: Double) {
        let delta = newProgress - progress
        guard delta > 0, delta < 0.05, !Self.reduceMotionPreferred else {
            progress = newProgress
            return
        }
        withAnimation(.linear(duration: 0.25)) {
            progress = newProgress
        }
    }

    private static var reduceMotionPreferred: Bool {
        let respectPreference =
            UserDefaults.standard.object(forKey: "nk.respectReducedMotion") as? Bool ?? true
        return AppMotion.reduceMotion(
            systemReduceMotion: UIAccessibility.isReduceMotionEnabled,
            respectPreference: respectPreference
        )
    }

    nonisolated static func normalizedQueue(_ source: [Song], selected song: Song) -> [Song] {
        var result = source
        if let index = QueueOccurrenceNavigator.resolvedIndex(for: song, in: result) {
            result[index] = song
        } else {
            result.insert(song, at: 0)
        }
        return result
    }

    nonisolated static func shuffledQueue(_ source: [Song], startingWith song: Song) -> [Song] {
        var rest = normalizedQueue(source, selected: song)
        if let selectedIndex = QueueOccurrenceNavigator.resolvedIndex(for: song, in: rest) {
            rest.remove(at: selectedIndex)
        }
        rest.shuffle()
        return [song] + rest
    }

    private func ensureQueueOccurrenceTokens() {
        guard queueOccurrenceTokens.count != queue.count else { return }
        let trackedIndex = currentQueueIndex
        queueOccurrenceTokens = queue.map { _ in UUID() }
        if let trackedIndex, queue.indices.contains(trackedIndex) {
            currentQueueOccurrenceToken = queueOccurrenceTokens[trackedIndex]
        } else {
            currentQueueIndex = nil
            currentQueueOccurrenceToken = nil
        }
    }

    private func setCurrentQueueIndex(_ index: Int?, matching song: Song? = nil) {
        ensureQueueOccurrenceTokens()
        guard let index,
              queue.indices.contains(index),
              song == nil || queue[index].id == song?.id
        else {
            currentQueueIndex = nil
            currentQueueOccurrenceToken = nil
            return
        }
        currentQueueIndex = index
        currentQueueOccurrenceToken = queueOccurrenceTokens[index]
    }

    private func replaceActiveQueue(
        songs: [Song],
        tokens: [UUID],
        selectedIndex: Int?
    ) {
        queue = songs
        queueOccurrenceTokens = tokens.count == songs.count
            ? tokens
            : songs.map { _ in UUID() }
        setCurrentQueueIndex(selectedIndex)
    }

    private func updateQueueOccurrence(
        for song: Song,
        context: [Song],
        preferredIndex: Int?
    ) {
        ensureQueueOccurrenceTokens()

        guard !context.isEmpty else {
            let retainedIndex = preferredIndex
                ?? (currentSong?.id == song.id ? currentQueueIndex : nil)
            let resolvedIndex = QueueOccurrenceNavigator.resolvedIndex(
                for: song,
                in: queue,
                preferredIndex: retainedIndex
            )
            setCurrentQueueIndex(resolvedIndex, matching: song)
            return
        }

        let normalizedContext = Self.normalizedQueue(context, selected: song)
        let isCurrentQueueContext = QueueOccurrenceNavigator.hasSameIDOrder(
            normalizedContext,
            queue
        )
        if isCurrentQueueContext {
            let resolvedIndex = QueueOccurrenceNavigator.resolvedIndex(
                for: song,
                in: queue,
                preferredIndex: preferredIndex,
                after: currentQueueIndex,
                preferFollowingMatch: preferredIndex == nil
            )
            setCurrentQueueIndex(resolvedIndex, matching: song)
            return
        }

        let normalizedTokens = normalizedContext.map { _ in UUID() }
        let selectedIndex = QueueOccurrenceNavigator.resolvedIndex(
            for: song,
            in: normalizedContext,
            preferredIndex: preferredIndex
        )
        if isShuffled, let selectedIndex {
            originalQueue = normalizedContext
            originalQueueOccurrenceTokens = normalizedTokens
            var entries = Array(zip(normalizedContext, normalizedTokens).enumerated())
            let selectedEntry = entries.remove(at: selectedIndex)
            entries.shuffle()
            let shuffledEntries = [selectedEntry] + entries
            replaceActiveQueue(
                songs: shuffledEntries.map { $0.element.0 },
                tokens: shuffledEntries.map { $0.element.1 },
                selectedIndex: 0
            )
        } else {
            originalQueue = []
            originalQueueOccurrenceTokens = []
            replaceActiveQueue(
                songs: normalizedContext,
                tokens: normalizedTokens,
                selectedIndex: selectedIndex
            )
        }
    }

    func play(song: Song, context: [Song] = []) {
        play(song: song, context: context, queueIndex: nil, resetTransitionVolume: true)
    }

    private func play(
        song: Song,
        context: [Song] = [],
        queueIndex: Int? = nil,
        resetTransitionVolume: Bool
    ) {
        DebugLogger.log("Play requested: \(song.title) (id: \(song.id))", category: .playback)
        let previousSongID = currentSong?.id
        let effectToResume = currentActiveEffect ?? deferredAIEffect
        suppressPlaybackEndedCallbacks()
        clearPreferredStreamResumeTime()
        if isRadioMode {
            RadioController.shared.stop()
        } else {
            RadioController.shared.cancelPendingPlaybackRequest()
        }
        stopRadioPlayer()
        stopStreamPlayer()
        isRadioMode = false
        radioArtworkURL = nil
        cancelPendingTransitionWork(resetVolume: resetTransitionVolume)
        avEngine.cancelCrossfade()
        avEngine.stop()
        instrumentalTask?.cancel()
        instrumentalTask = nil
        separationGeneration &+= 1
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        VocalSeparator.shared.cleanupRealtimeTemp()
        reportPlayCount(for: song.id)
        enrichSongMetadataIfNeeded(for: song)
        if previousSongID != song.id {
            var excludeIDs = activeSongIDs()
            excludeIDs.insert(song.id)
            scheduleIdleCacheCompression(excluding: excludeIDs)
        }
        preparedStemSongID = nil
        if previousSongID != song.id, aiEnabled, aiAutoAnalyze {
            deferredAIEffect = effectToResume
            if effectToResume != nil {
                temporarilyDisableAIEffects()
            }
        }
        progress = 0
        updateQueueOccurrence(for: song, context: context, preferredIndex: queueIndex)
        if currentSong?.id != song.id {
            withAnimation(.easeInOut(duration: 0.32)) {
                currentSong = song
            }
        } else {
            currentSong = song
        }
        warmPlayerArtwork(for: song)
        checkEasterEgg(for: song)
        // Songs with a remote source use the non-decompressing lookup; a
        // compressed-only cache falls through to startStreamPlayback, whose
        // cache-hit path decompresses off the main thread.
        let fileURL = song.audioURL != nil
            ? immediateLocalPlaybackFileURL(for: song)
            : localPlaybackFileURL(for: song)
        if let fileURL, let stems = stemsForCachedAIMode(song: song) {
            instrumentalTask?.cancel()
            instrumentalTask = nil
            separationGeneration &+= 1
            VocalSeparator.shared.cancel()
            preparedStemSongID = song.id
            restoreDeferredAIEffectIfNeeded(for: song.id, applyImmediately: false)
            currentPlaybackURL = fileURL
            configureAudioSessionCategory()
            activateAudioSession()
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
            avEngine.playStems(
                originalURL: fileURL,
                vocalsURL: stems.vocals, instrumentsURL: stems.instruments,
                startOffset: stems.startOffset,
                temporaryLease: stems.temporaryLease,
                shouldPlay: { [weak self] in self?.isPlaybackRequested == true },
                isRequestValid: { [weak self] in
                    self?.isAIStemPlaybackRequested(for: song.id) == true
                },
                onCancelled: { [weak self] in
                    self?.handleAIStemLoadCancellation(for: song.id)
                },
                onReady: { [weak self] in
                    guard let self else { return }
                    if aiStemSwitchInFlightSongID == song.id {
                        aiStemSwitchInFlightSongID = nil
                    }
                    applyAIMixVolumes()
                    #if canImport(UIKit)
                        endTrackTransitionBackgroundTask()
                    #endif
                }
            )
            aiStemSwitchInFlightSongID = song.id
            setPlaybackState(
                playing: true,
                buffering: false,
                reloadArtwork: true,
                reason: "play.cachedStems"
            )
            return
        }
        if let fileURL {
            startPlayingFile(fileURL)
            prepareBackgroundStemPlaybackIfPossible(for: song)
            applyMLSeparationIfNeeded()
            return
        }
        guard let remoteURL = song.audioURL else {
            #if canImport(UIKit)
                endTrackTransitionBackgroundTask()
            #endif
            return
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        startStreamPlayback(url: remoteURL, songID: song.id, expectedDuration: expectedDuration)
        if aiEnabled {
            if anyAIEffectActive {
                applyMLSeparationIfNeeded()
            } else if aiAutoAnalyze {
                triggerBackgroundAnalysis(for: song)
            }
        }
    }

    func playNext(song: Song) {
        guard !isRadioMode else {
            play(song: song)
            return
        }
        guard let current = currentSong else {
            play(song: song)
            return
        }
        ensureQueueOccurrenceTokens()
        var baseIndex = QueueOccurrenceNavigator.resolvedIndex(
            for: current,
            in: queue,
            preferredIndex: currentQueueIndex
        )
        if baseIndex == nil {
            let currentToken = currentQueueOccurrenceToken ?? UUID()
            queue.insert(current, at: 0)
            queueOccurrenceTokens.insert(currentToken, at: 0)
            baseIndex = 0
            setCurrentQueueIndex(0, matching: current)
        }
        guard let baseIndex else { return }

        let insertedToken = UUID()
        let insertIndex = min(baseIndex + 1, queue.count)
        queue.insert(song, at: insertIndex)
        queueOccurrenceTokens.insert(insertedToken, at: insertIndex)
        setCurrentQueueIndex(baseIndex, matching: current)

        if !originalQueue.isEmpty,
           originalQueueOccurrenceTokens.count == originalQueue.count,
           let currentToken = currentQueueOccurrenceToken,
           let originalIndex = originalQueueOccurrenceTokens.firstIndex(of: currentToken)
        {
            let originalInsertIndex = min(originalIndex + 1, originalQueue.count)
            originalQueue.insert(song, at: originalInsertIndex)
            originalQueueOccurrenceTokens.insert(insertedToken, at: originalInsertIndex)
        }
        // Drop any prepared/in-flight crossfade to the previous next track so
        // the coordinator re-prepares against the newly inserted song.
        cancelPendingTransitionWork()
    }

    private func startPlayingFile(_ url: URL, startAt: TimeInterval = 0) {
        suppressPlaybackEndedCallbacks()
        stopRadioPlayer()
        stopStreamPlayer()
        instrumentalTask?.cancel()
        instrumentalTask = nil
        separationGeneration &+= 1
        VocalSeparator.shared.cancel()
        streamStartedAt = nil
        currentPlaybackURL = url
        configureAudioSessionCategory()
        activateAudioSession()
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        avEngine.play(
            url: url,
            startAt: max(0, startAt),
            shouldPlay: { [weak self] in self?.isPlaybackRequested == true }
        ) { [weak self] in
            #if canImport(UIKit)
                self?.endTrackTransitionBackgroundTask()
            #endif
        }
        VocalSeparator.shared.cleanupRealtimeTemp()
        setPlaybackState(
            playing: true,
            buffering: false,
            reloadArtwork: true,
            reason: "startPlayingFile"
        )
        DebugLogger.log("Playing file: \(url.lastPathComponent)", category: .playback)
        CacheManager.shared.recordAccess(for: url)
        if let song = currentSong, aiEnabled, aiAutoAnalyze, !anyAIEffectActive {
            triggerBackgroundAnalysis(for: song)
            prepareBackgroundStemPlaybackIfPossible(for: song)
        }
    }

    private func warmPlayerArtwork(for song: Song) {
        let urls = [
            displayImageURL(for: song, variant: .thumbnail),
            displayImageURL(for: song, variant: .card),
        ].compactMap { $0 }
        warmPlayerArtworkURLs(urls)
    }

    private func warmPlayerArtworkURLs(_ urls: [URL]) {
        let now = Date()
        warmedPlayerArtworkAt = warmedPlayerArtworkAt.filter { now.timeIntervalSince($0.value) < 60 }
        for url in urls {
            let key = url.absoluteString
            guard warmedPlayerArtworkAt[key] == nil, playerArtworkWarmupTasks[key] == nil else { continue }
            warmedPlayerArtworkAt[key] = now
            playerArtworkWarmupTasks[key] = SDWebImageManager.shared.loadImage(
                with: url,
                options: [.highPriority],
                context: ImageCacheConfig.visibleImageContext,
                progress: nil
            ) { [weak self] _, _, _, _, _, _ in
                Task { @MainActor in
                    _ = self?.playerArtworkWarmupTasks.removeValue(forKey: key)
                }
            }
        }
    }

    private func cancelPlayerArtworkWarmups() {
        playerArtworkWarmupTasks.values.forEach { $0.cancel() }
        playerArtworkWarmupTasks.removeAll()
    }

    private func fallBackToMainPlayback(for song: Song, startAt: TimeInterval) {
        suppressPlaybackEndedCallbacks()
        stopRadioPlayer()
        stopStreamPlayer()
        avEngine.stop()
        aiStemSwitchInFlightSongID = nil
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        VocalSeparator.shared.cleanupRealtimeTemp()
        if avEngine.mode == .aiStems {
            avEngine.revertToMain()
        }
        let resumeAt = max(0, startAt.isFinite ? startAt : 0)
        if let fileURL = localPlaybackFileURL(for: song) {
            startPlayingFile(fileURL, startAt: resumeAt)
            return
        }
        guard let remoteURL = song.audioURL else {
            setPlaybackState(
                playing: false,
                buffering: false,
                reason: "fallBackToMainPlayback.noRemoteURL"
            )
            return
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        startStreamPlayback(url: remoteURL, songID: song.id, expectedDuration: expectedDuration, startAt: resumeAt)
    }

    /// Returns true when a pause request matched an active or resumable playback path.
    @discardableResult
    private func pauseCurrentPlayback(source: String = #function) -> Bool {
        cancelPendingAutoplayFetch()
        if !handlingAudioSessionInterruption {
            wasPlayingBeforeInterruption = false
        }
        if isRadioMode {
            let wasActive = radioPlaybackRequested || isPlaying || isBuffering
            guard wasActive else {
                setPlaybackState(
                    playing: false,
                    buffering: false,
                    forceNowPlayingUpdate: true,
                    reason: "pause.radio.alreadyPaused.\(source)"
                )
                return true
            }
            lastKnownPlaybackTime = activePlaybackTime()
            // A live stream has no useful paused position. Tear down the item
            // so the next Play reconnects at the live edge.
            stopRadioPlayer()
            setPlaybackState(
                playing: false,
                buffering: false,
                forceNowPlayingUpdate: true,
                reason: "stop.radio.\(source)"
            )
            return true
        }
        if isRemotePlaybackCaching {
            let wasActive = streamPlaybackRequested || isBuffering
            streamPlaybackRequested = false
            if let preferredResume = preferredStreamResumeTime(for: currentSong) {
                lastKnownPlaybackTime = preferredResume
            }
            setPlaybackState(
                playing: false,
                buffering: false,
                forceNowPlayingUpdate: true,
                reason: "pause.cachedRemote.\(source)"
            )
            return wasActive
        }
        if isStreamMode {
            let wasActive = streamPlaybackRequested || isPlaying || isBuffering
            guard let player = streamPlayer else {
                streamPlaybackRequested = false
                setPlaybackState(
                    playing: false,
                    buffering: false,
                    forceNowPlayingUpdate: true,
                    reason: "pause.stream.noPlayer.\(source)"
                )
                return wasActive
            }
            guard wasActive else {
                setPlaybackState(
                    playing: false,
                    buffering: false,
                    forceNowPlayingUpdate: true,
                    reason: "pause.stream.alreadyPaused.\(source)"
                )
                return true
            }
            cancelPendingTransitionWork()
            streamPlaybackRequested = false
            lastKnownPlaybackTime = activePlaybackTime()
            player.pause()
            setPlaybackState(playing: false, buffering: false, reason: "pause.stream.\(source)")
            return true
        }
        guard isPlaying else {
            guard currentSong != nil else { return false }
            setPlaybackState(
                playing: false,
                buffering: false,
                forceNowPlayingUpdate: true,
                reason: "pause.file.alreadyPaused.\(source)"
            )
            return true
        }
        cancelPendingTransitionWork()
        lastKnownPlaybackTime = activePlaybackTime()
        avEngine.pause()
        setPlaybackState(playing: false, buffering: false, reason: "pause.file.\(source)")
        return true
    }

    /// Returns true when a resume request could be applied to the current playback path.
    @discardableResult
    private func resumeCurrentPlayback(source: String = #function) -> Bool {
        cancelPendingAutoplayFetch()
        if isRadioMode {
            guard let player = radioPlayer else {
                guard let streamURL = currentPlaybackURL else {
                    radioPlaybackRequested = false
                    setPlaybackState(
                        playing: false,
                        buffering: false,
                        reason: "resume.radio.noURL.\(source)"
                    )
                    return false
                }
                startRadio(url: streamURL)
                return true
            }
            guard !radioPlaybackRequested || !isPlaying || isBuffering else {
                setPlaybackState(
                    playing: true,
                    buffering: false,
                    forceNowPlayingUpdate: true,
                    reason: "resume.radio.alreadyPlaying.\(source)"
                )
                return true
            }
            configureAudioSessionCategory()
            activateAudioSession()
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
            radioPlaybackRequested = true
            setPlaybackState(playing: false, buffering: true, reason: "resume.radio.buffering.\(source)")
            player.playImmediately(atRate: 1.0)
            refreshManagedPlayerState(player, kind: .radio)
            return true
        }
        if isRemotePlaybackCaching {
            guard !streamPlaybackRequested || !isBuffering else {
                setPlaybackState(
                    playing: false,
                    buffering: true,
                    forceNowPlayingUpdate: true,
                    reason: "resume.cachedRemote.alreadyPreparing.\(source)"
                )
                return true
            }
            configureAudioSessionCategory()
            activateAudioSession()
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
            streamPlaybackRequested = true
            setPlaybackState(
                playing: false,
                buffering: true,
                forceNowPlayingUpdate: true,
                reason: "resume.cachedRemote.buffering.\(source)"
            )
            return true
        }
        if isStreamMode {
            guard let player = streamPlayer else {
                streamPlaybackRequested = false
                setPlaybackState(playing: false, buffering: false, reason: "resume.stream.noPlayer.\(source)")
                return false
            }
            guard !streamPlaybackRequested || !isPlaying || isBuffering else {
                setPlaybackState(
                    playing: true,
                    buffering: false,
                    forceNowPlayingUpdate: true,
                    reason: "resume.stream.alreadyPlaying.\(source)"
                )
                return true
            }
            configureAudioSessionCategory()
            activateAudioSession()
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
            streamPlaybackRequested = true
            setPlaybackState(playing: false, buffering: true, reason: "resume.stream.buffering.\(source)")
            player.playImmediately(atRate: 1.0)
            refreshManagedPlayerState(player, kind: .stream)
            return true
        }
        guard currentSong != nil else { return false }
        if !isPlaying, avEngine.currentURL == nil, let song = currentSong,
           let fileURL = localPlaybackFileURL(for: song)
        {
            let resumeAt = preferredStreamResumeTime(for: song) ?? lastKnownPlaybackTime
            clearPreferredStreamResumeTime()
            startPlayingFile(fileURL, startAt: resumeAt)
            return true
        }
        guard !isPlaying else {
            setPlaybackState(
                playing: true,
                buffering: false,
                forceNowPlayingUpdate: true,
                reason: "resume.file.alreadyPlaying.\(source)"
            )
            return true
        }
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        avEngine.resume()
        setPlaybackState(playing: true, buffering: false, reason: "resume.file.\(source)")
        return true
    }

    @discardableResult
    func togglePlayPause(source: String = #function) -> Bool {
        if isPlaybackRequested {
            return pauseCurrentPlayback(source: "toggle.\(source)")
        }
        return resumeCurrentPlayback(source: "toggle.\(source)")
    }

    func pauseIfPlaying() {
        guard isPlaybackRequested else { return }
        pauseCurrentPlayback(source: "pauseIfPlaying")
    }

    func seek(to fraction: Double) {
        guard fraction.isFinite, (0.0 ... 1.0).contains(fraction) else { return }
        if isRadioMode { return }
        suppressTransitionAfterSeek = true
        suppressPlaybackEndedCallbacks()
        progress = fraction
        if isStreamMode {
            guard let player = streamPlayer else { return }
            let totalDur = playbackDuration
            guard totalDur.isFinite, totalDur > 0 else { return }
            let targetSeconds = min(totalDur * fraction, totalDur - 1.5)
            guard targetSeconds >= 0 else { return }
            setPreferredStreamResumeTime(targetSeconds, for: currentSong?.id)
            let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            if anyAIEffectActive {
                applyMLSeparationIfNeeded()
            }
            updateNowPlayingInfo(reloadArtwork: false)
            return
        }
        if isRemotePlaybackCaching, let song = currentSong, song.duration > 0 {
            let totalDur = Double(song.duration)
            let targetSeconds = min(totalDur * fraction, totalDur - 1.5)
            guard targetSeconds >= 0 else { return }
            setPreferredStreamResumeTime(targetSeconds, for: song.id)
            updateNowPlayingInfo(reloadArtwork: false)
            return
        }
        cancelPendingTransitionWork()
        let audioDur = avEngine.duration
        let totalDur: Double
        if audioDur.isFinite, audioDur > 0 {
            totalDur = audioDur
        } else if let song = currentSong, song.duration > 0 {
            totalDur = Double(song.duration)
        } else {
            return
        }
        let target = min(totalDur * fraction, totalDur - 1.5)
        guard target >= 0 else { return }
        var needsAIRefresh = false
        if avEngine.mode == .aiStems {
            if !avEngine.seek(to: target) {
                avEngine.revertToMain()
                _ = avEngine.seek(to: target)
                needsAIRefresh = anyAIEffectActive
            }
        } else {
            _ = avEngine.seek(to: target)
            needsAIRefresh = anyAIEffectActive
        }
        if needsAIRefresh {
            applyMLSeparationIfNeeded()
        }
        updateNowPlayingInfo(reloadArtwork: false)
    }

    func playNextOrRandom() {
        if isRadioMode { return }
        cancelPendingAutoplayFetch()
        transitionCoordinator.reset()
        #if canImport(UIKit)
            beginTrackTransitionBackgroundTask()
        #endif
        configureAudioSessionCategory()
        activateAudioSession()
        if repeatMode == .one, let current = currentSong {
            play(
                song: current,
                queueIndex: currentQueueIndex,
                resetTransitionVolume: true
            )
            return
        }
        if let current = currentSong,
           let next = QueueOccurrenceNavigator.nextSelection(
               currentSong: current,
               currentIndex: currentQueueIndex,
               queue: queue,
               wrapsAtEnd: repeatMode == .all
           )
        {
            play(
                song: next.song,
                queueIndex: next.index,
                resetTransitionVolume: true
            )
        } else if autoplayEnabled {
            fetchRandomTrending()
        } else {
            avEngine.pause()
            setPlaybackState(
                playing: false,
                buffering: false,
                reason: "playNextOrRandom.endOfQueue"
            )
            #if canImport(UIKit)
                endTrackTransitionBackgroundTask()
            #endif
        }
    }

    func playPrevious() {
        if isRadioMode { return }
        guard let current = currentSong,
              let previous = QueueOccurrenceNavigator.previousSelection(
                  currentSong: current,
                  currentIndex: currentQueueIndex,
                  queue: queue
              )
        else {
            seek(to: 0)
            return
        }
        play(
            song: previous.song,
            queueIndex: previous.index,
            resetTransitionVolume: true
        )
    }

    func toggleRepeat() {
        repeatMode = repeatMode.next()
    }

    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            ensureQueueOccurrenceTokens()
            originalQueue = queue
            originalQueueOccurrenceTokens = queueOccurrenceTokens
            guard let current = currentSong,
                  let selectedIndex = QueueOccurrenceNavigator.resolvedIndex(
                      for: current,
                      in: queue,
                      preferredIndex: currentQueueIndex
                  )
            else { return }
            var entries = Array(zip(queue, queueOccurrenceTokens).enumerated())
            let selectedEntry = entries.remove(at: selectedIndex)
            entries.shuffle()
            let shuffledEntries = [selectedEntry] + entries
            replaceActiveQueue(
                songs: shuffledEntries.map { $0.element.0 },
                tokens: shuffledEntries.map { $0.element.1 },
                selectedIndex: 0
            )
        } else if !originalQueue.isEmpty {
            let activeToken = currentQueueOccurrenceToken
            let restoredTokens = originalQueueOccurrenceTokens.count == originalQueue.count
                ? originalQueueOccurrenceTokens
                : originalQueue.map { _ in UUID() }
            let restoredIndex = activeToken.flatMap { restoredTokens.firstIndex(of: $0) }
                ?? currentSong.flatMap {
                    QueueOccurrenceNavigator.resolvedIndex(for: $0, in: originalQueue)
                }
            replaceActiveQueue(
                songs: originalQueue,
                tokens: restoredTokens,
                selectedIndex: restoredIndex
            )
            originalQueue = []
            originalQueueOccurrenceTokens = []
        }
        cancelPendingTransitionWork()
    }

    func playInOrder(song: Song, context: [Song]) {
        isShuffled = false
        originalQueue = []
        originalQueueOccurrenceTokens = []
        play(song: song, context: context)
    }

    func playShuffled(from songs: [Song]) {
        guard !songs.isEmpty else { return }
        let selectedIndex = Int.random(in: songs.indices)
        let tokens = songs.map { _ in UUID() }
        var entries = Array(zip(songs, tokens).enumerated())
        let selectedEntry = entries.remove(at: selectedIndex)
        entries.shuffle()
        let shuffledEntries = [selectedEntry] + entries
        isShuffled = true
        originalQueue = songs
        originalQueueOccurrenceTokens = tokens
        replaceActiveQueue(
            songs: shuffledEntries.map { $0.element.0 },
            tokens: shuffledEntries.map { $0.element.1 },
            selectedIndex: 0
        )
        play(
            song: shuffledEntries[0].element.0,
            queueIndex: 0,
            resetTransitionVolume: true
        )
    }

    func toggleAutoplay() {
        autoplayEnabled.toggle()
    }

    func moveInUpNext(from source: IndexSet, to destination: Int) {
        ensureQueueOccurrenceTokens()
        guard let current = currentSong,
              let baseIdx = QueueOccurrenceNavigator.resolvedIndex(
                  for: current,
                  in: queue,
                  preferredIndex: currentQueueIndex
              )
        else { return }
        let upNextStart = baseIdx + 1
        guard upNextStart < queue.count else { return }
        var upNext = Array(queue[upNextStart...])
        var upNextTokens = Array(queueOccurrenceTokens[upNextStart...])
        upNext.move(fromOffsets: source, toOffset: destination)
        upNextTokens.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue[..<upNextStart]) + upNext
        queueOccurrenceTokens = Array(queueOccurrenceTokens[..<upNextStart]) + upNextTokens
        setCurrentQueueIndex(baseIdx, matching: current)
        cancelPendingTransitionWork()
    }

    func removeFromUpNext(at offsets: IndexSet) {
        ensureQueueOccurrenceTokens()
        guard let current = currentSong,
              let baseIdx = QueueOccurrenceNavigator.resolvedIndex(
                  for: current,
                  in: queue,
                  preferredIndex: currentQueueIndex
              )
        else { return }
        let upNextStart = baseIdx + 1
        guard upNextStart < queue.count else { return }
        var upNext = Array(queue[upNextStart...])
        var upNextTokens = Array(queueOccurrenceTokens[upNextStart...])
        let removedTokens = Set(offsets.compactMap { offset in
            upNextTokens.indices.contains(offset) ? upNextTokens[offset] : nil
        })
        upNext.remove(atOffsets: offsets)
        upNextTokens.remove(atOffsets: offsets)
        queue = Array(queue[..<upNextStart]) + upNext
        queueOccurrenceTokens = Array(queueOccurrenceTokens[..<upNextStart]) + upNextTokens
        setCurrentQueueIndex(baseIdx, matching: current)
        if !removedTokens.isEmpty,
           originalQueueOccurrenceTokens.count == originalQueue.count
        {
            let retained = zip(originalQueue, originalQueueOccurrenceTokens).filter {
                !removedTokens.contains($0.1)
            }
            originalQueue = retained.map(\.0)
            originalQueueOccurrenceTokens = retained.map(\.1)
        }
        cancelPendingTransitionWork()
    }

    private func observeManagedPlayer(
        _ player: AVPlayer,
        item: AVPlayerItem,
        kind: ManagedAVPlayerKind
    ) {
        let statusHandler: (AVPlayerItem.Status) -> Void = { [weak self, weak player, weak item] status in
            guard let self, let player, let item else { return }
            handleManagedItemStatus(status, player: player, item: item, kind: kind)
        }
        let stateHandler: () -> Void = { [weak self, weak player] in
            guard let self, let player else { return }
            refreshManagedPlayerState(player, kind: kind)
        }

        switch kind {
        case .radio:
            radioPlayerCancellables.removeAll()
            item.publisher(for: \.status, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .sink(receiveValue: statusHandler)
                .store(in: &radioPlayerCancellables)
            item.publisher(for: \.isPlaybackBufferEmpty, options: [.new])
                .receive(on: DispatchQueue.main)
                .sink { _ in stateHandler() }
                .store(in: &radioPlayerCancellables)
            item.publisher(for: \.isPlaybackLikelyToKeepUp, options: [.new])
                .receive(on: DispatchQueue.main)
                .sink { _ in stateHandler() }
                .store(in: &radioPlayerCancellables)
            player.publisher(for: \.timeControlStatus, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .sink { _ in stateHandler() }
                .store(in: &radioPlayerCancellables)
        case .stream:
            streamPlayerCancellables.removeAll()
            item.publisher(for: \.status, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .sink(receiveValue: statusHandler)
                .store(in: &streamPlayerCancellables)
            item.publisher(for: \.isPlaybackBufferEmpty, options: [.new])
                .receive(on: DispatchQueue.main)
                .sink { _ in stateHandler() }
                .store(in: &streamPlayerCancellables)
            item.publisher(for: \.isPlaybackLikelyToKeepUp, options: [.new])
                .receive(on: DispatchQueue.main)
                .sink { _ in stateHandler() }
                .store(in: &streamPlayerCancellables)
            player.publisher(for: \.timeControlStatus, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .sink { _ in stateHandler() }
                .store(in: &streamPlayerCancellables)
        }
    }

    private func handleManagedItemStatus(
        _ status: AVPlayerItem.Status,
        player: AVPlayer,
        item: AVPlayerItem,
        kind: ManagedAVPlayerKind
    ) {
        guard isCurrentManagedPlayer(player, kind: kind) else { return }
        switch status {
        case .readyToPlay:
            refreshManagedPlayerState(player, kind: kind)
        case .failed:
            handleManagedPlayerFailure(player: player, item: item, kind: kind)
        case .unknown:
            refreshManagedPlayerState(player, kind: kind)
        @unknown default:
            refreshManagedPlayerState(player, kind: kind)
        }
    }

    private func refreshManagedPlayerState(_ player: AVPlayer, kind: ManagedAVPlayerKind) {
        guard isCurrentManagedPlayer(player, kind: kind) else { return }
        guard let item = player.currentItem else {
            setPlaybackState(playing: false, buffering: false, reason: "managed.\(kind).noItem")
            return
        }
        if item.status == .failed {
            handleManagedPlayerFailure(player: player, item: item, kind: kind)
            return
        }
        let playbackRequested = playbackRequested(for: kind)
        guard playbackRequested else {
            setPlaybackState(playing: false, buffering: false, reason: "managed.\(kind).notRequested")
            return
        }
        if player.timeControlStatus == .playing {
            setPlaybackState(playing: true, buffering: false, reason: "managed.\(kind).playing")
        } else {
            setPlaybackState(playing: false, buffering: true, reason: "managed.\(kind).buffering")
        }
    }

    private func handleManagedPlayerFailure(
        player: AVPlayer,
        item: AVPlayerItem,
        kind: ManagedAVPlayerKind
    ) {
        guard isCurrentManagedPlayer(player, kind: kind) else { return }
        let message = item.error?.localizedDescription
            ?? player.error?.localizedDescription
            ?? "unknown error"
        switch kind {
        case .radio:
            DebugLogger.log("Radio AVPlayer failed: \(message)", category: .playback)
            radioPlaybackRequested = false
        case .stream:
            DebugLogger.log("Stream AVPlayer failed: \(message)", category: .playback)
            streamPlaybackRequested = false
        }
        setPlaybackState(playing: false, buffering: false, reason: "managed.\(kind).failure")
    }

    private func isCurrentManagedPlayer(_ player: AVPlayer, kind: ManagedAVPlayerKind) -> Bool {
        switch kind {
        case .radio:
            radioPlayer === player
        case .stream:
            streamPlayer === player
        }
    }

    private func playbackRequested(for kind: ManagedAVPlayerKind) -> Bool {
        switch kind {
        case .radio:
            radioPlaybackRequested
        case .stream:
            streamPlaybackRequested
        }
    }

    func playRadio(streamURL: URL, song: Song, artworkURL: URL?) {
        resetEasterEggWork()
        setCurrentQueueIndex(nil)
        let alreadyOnSameStation = isRadioMode && currentSong?.id == song.id
        if alreadyOnSameStation {
            currentSong = song
            radioArtworkURL = artworkURL
            if radioPlayer == nil || !radioPlaybackRequested {
                startRadio(url: streamURL)
            } else {
                updateNowPlayingInfo(reloadArtwork: true)
            }
            return
        }
        cancelPendingTransitionWork()
        avEngine.stop()
        stopStreamPlayer()
        instrumentalTask?.cancel()
        instrumentalTask = nil
        preparedStemSongID = nil
        deferredAIEffect = nil
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        scheduleIdleCacheCompression(excluding: Set<String>())
        isRadioMode = true
        radioArtworkURL = artworkURL
        progress = 0
        queue = []
        queueOccurrenceTokens = []
        originalQueue = []
        originalQueueOccurrenceTokens = []
        withAnimation(.easeInOut(duration: 0.32)) { currentSong = song }
        startRadio(url: streamURL)
    }

    private func startRadio(url: URL) {
        stopRadioPlayer()
        currentPlaybackURL = url
        configureAudioSessionCategory()
        activateAudioSession()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        if #available(iOS 15.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        player.volume = 1.0
        radioPlayer = player
        radioPlaybackRequested = true
        setPlaybackState(
            playing: false,
            buffering: true,
            reloadArtwork: true,
            reason: "startRadio"
        )
        observeManagedPlayer(player, item: item, kind: .radio)
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        player.playImmediately(atRate: 1.0)
    }

    private func stopRadioPlayer() {
        radioPlayerCancellables.removeAll()
        radioPlaybackRequested = false
        if let existing = radioTimeObserver {
            existing.player.removeTimeObserver(existing.token)
            radioTimeObserver = nil
        }
        radioPlayer?.pause()
        radioPlayer?.replaceCurrentItem(with: nil)
        radioPlayer = nil
    }

    private func startStreamPlayback(
        url: URL,
        songID: String,
        expectedDuration: TimeInterval? = nil,
        startAt: TimeInterval = 0,
        autoplay: Bool = true
    ) {
        stopStreamPlayer()
        stopRadioPlayer()
        avEngine.stop()
        currentPlaybackURL = url
        DebugLogger.log(
            "Starting cached remote playback for \(songID): source=\(playbackSourceDescription(url)), startAt=\(startAt), autoplay=\(autoplay)",
            category: .playback
        )
        configureAudioSessionCategory()
        activateAudioSession()
        streamStartedAt = Date()
        streamPlaybackRequested = autoplay
        setPlaybackState(
            playing: false,
            buffering: autoplay,
            reloadArtwork: true,
            reason: "startStreamPlayback"
        )
        if startAt > 0 {
            setPreferredStreamResumeTime(startAt, for: songID)
        } else {
            clearPreferredStreamResumeTime()
        }
        if autoplay {
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        }

        remotePlaybackCacheTask?.cancel()
        // Token guard: replaying the same URL cancels the old task, whose
        // cancellation handler must not reset state owned by the new request.
        let requestToken = UUID()
        remotePlaybackCacheToken = requestToken
        remotePlaybackCacheTask = Task { [weak self] in
            do {
                let cachedURL = try await Self.cacheRemoteAudio(
                    from: url,
                    songID: songID,
                    expectedDuration: expectedDuration
                )
                await MainActor.run { [weak self] in
                    guard let self, remotePlaybackCacheToken == requestToken else { return }
                    guard currentSong?.id == songID, currentPlaybackURL == url else { return }
                    remotePlaybackCacheTask = nil
                    if streamPlaybackRequested {
                        let resumeAt = preferredStreamResumeTime(for: currentSong) ?? startAt
                        clearPreferredStreamResumeTime()
                        startPlayingFile(cachedURL, startAt: resumeAt)
                    } else {
                        currentPlaybackURL = cachedURL
                        setPlaybackState(
                            playing: false,
                            buffering: false,
                            forceNowPlayingUpdate: true,
                            reason: "startStreamPlayback.cachedPaused"
                        )
                    }
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, remotePlaybackCacheToken == requestToken else { return }
                    guard currentSong?.id == songID else { return }
                    guard currentPlaybackURL == url else { return }
                    remotePlaybackCacheTask = nil
                    streamPlaybackRequested = false
                    setPlaybackState(
                        playing: false,
                        buffering: false,
                        forceNowPlayingUpdate: true,
                        reason: "startStreamPlayback.cancelled"
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, remotePlaybackCacheToken == requestToken else { return }
                    guard currentSong?.id == songID else { return }
                    guard currentPlaybackURL == url else { return }
                    remotePlaybackCacheTask = nil
                    streamPlaybackRequested = false
                    DebugLogger.log(
                        "Remote playback cache failed for \(songID): \(error.localizedDescription)",
                        category: .playback
                    )
                    setPlaybackState(
                        playing: false,
                        buffering: false,
                        forceNowPlayingUpdate: true,
                        reason: "startStreamPlayback.cacheFailed"
                    )
                }
            }
        }
    }

    // nonisolated: cache validation, file moves, and possible decompression
    // are blocking file I/O that must stay off the main actor.
    private nonisolated static func cacheRemoteAudio(
        from remoteURL: URL,
        songID: String,
        expectedDuration: TimeInterval?
    ) async throws -> URL {
        if let cachedURL = AudioCacheStore.playableMainURL(
            for: songID,
            expectedRemoteURL: remoteURL,
            expectedDuration: expectedDuration
        ) {
            DebugLogger.log("Remote playback cache hit for \(songID)", category: .cache)
            return cachedURL
        }

        let lease = AudioCacheStore.beginMainWrite(songID: songID, sourceURL: remoteURL)
        defer { AudioCacheStore.cancelMainWrite(lease) }
        DebugLogger.log("Remote playback cache start for \(songID)", category: .cache)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (temporaryURL, response) = try await session.download(from: remoteURL)
        try Task.checkCancellation()
        guard AudioCacheStore.acceptsAudioResponse(response) else {
            throw RemotePlaybackCacheError.invalidResponse
        }
        guard AudioCacheStore.ownsMainWrite(lease) else {
            throw CancellationError()
        }

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: lease.mainStagingURL)
        } catch {
            try FileManager.default.copyItem(at: temporaryURL, to: lease.mainStagingURL)
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        try Task.checkCancellation()

        guard AudioCacheStore.isPlayableAudioFile(at: lease.mainStagingURL) else {
            throw RemotePlaybackCacheError.invalidAudio
        }
        try Task.checkCancellation()

        guard try AudioCacheStore.commitMainWrite(lease) else {
            throw CancellationError()
        }
        DebugLogger.log("Remote playback cache complete for \(songID)", category: .cache)
        return lease.mainURL
    }

    private enum RemotePlaybackCacheError: LocalizedError {
        case invalidResponse
        case invalidAudio

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Remote audio response was not playable"
            case .invalidAudio:
                "Downloaded remote audio was not playable"
            }
        }
    }

    private func stopStreamPlayer() {
        remotePlaybackCacheTask?.cancel()
        remotePlaybackCacheTask = nil
        remotePlaybackCacheToken = nil
        streamPlayerCancellables.removeAll()
        streamPlaybackRequested = false
        if let observer = streamEndObserver {
            NotificationCenter.default.removeObserver(observer)
            streamEndObserver = nil
        }
        streamFadeTimer?.invalidate()
        streamFadeTimer = nil
        streamPlayer?.pause()
        streamPlayer?.replaceCurrentItem(with: nil)
        streamPlayer = nil
        streamStartedAt = nil
    }

    private func fadeOutStreamPlayer(duration: TimeInterval) {
        guard streamPlayer != nil else { return }
        streamFadeTimer?.invalidate()
        let interval = AVEnginePlayback.transitionTimerInterval
        let steps = max(1, Int((duration / interval).rounded(.up)))
        let counter = TimerStepCounter()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            let finished = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return true }
                counter.step += 1
                let t = Float(counter.step) / Float(max(1, steps))
                self.streamPlayer?.volume = max(0, 1.0 - t)
                if t >= 1.0 {
                    self.streamFadeTimer = nil
                    return true
                }
                return false
            }
            if finished { timer.invalidate() }
        }
        streamFadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func updateRadioMetadata(song: Song, artworkURL: URL?) {
        guard isRadioMode else { return }
        currentSong = song
        radioArtworkURL = artworkURL
        updateNowPlayingInfo(reloadArtwork: true)
    }

    func displayImageURL(for song: Song, variant: ArtworkImageVariant = .card) -> URL? {
        if isRadioMode, currentSong?.id == song.id, let art = radioArtworkURL {
            return ArtworkURLBuilder.variantURL(from: art, variant: variant) ?? art
        }
        switch variant {
        case .row:
            return song.rowImageURL
        case .thumbnail:
            return song.thumbnailURL
        case .hero:
            return song.heroImageURL
        case .fullHD:
            return song.fullHDImageURL
        default:
            return song.imageURL
        }
    }

    func clearCache() {
        DebugLogger.log("Clearing all cache", category: .cache)
        cancelPendingTransitionWork()
        cancelPlayerArtworkWarmups()
        warmedPlayerArtworkAt.removeAll()
        cacheCompressionTask?.cancel()
        remotePlaybackCacheTask?.cancel()
        instrumentalTask?.cancel()
        instrumentalTask = nil
        resetEasterEggWork()
        preparedStemSongID = nil
        deferredAIEffect = nil
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        revertAIPlaybackToMain()
        VocalSeparator.shared.cleanupRealtimeTemp()
        AudioCacheStore.clearAllCache()
        #if canImport(UIKit)
            AudioPlayerManager.artworkCache.removeAllObjects()
            nowPlayingArtwork = nil
        #endif
        CacheManager.shared.refreshSizes()
    }

    private static func cleanupOrphanPartialCacheFiles() {
        AudioCacheStore.cleanupLegacyArtifacts()
    }

    private func stemsForCachedAIMode(song: Song) -> CachedStems? {
        let hasRequestedEffect = anyAIEffectActive || deferredAIEffect != nil
        guard aiEnabled, hasRequestedEffect, !isRadioMode, VocalSeparator.shared.isAvailable else {
            return nil
        }
        return cachedStems(for: song, sourceURL: localPlaybackFileURL(for: song))
    }

    private func triggerBackgroundAnalysis(for song: Song) {
        guard aiEnabled, aiAutoAnalyze, !isRadioMode, !anyAIEffectActive else { return }
        guard VocalSeparator.shared.isAvailable else { return }

        if cachedStems(for: song, sourceURL: localPlaybackFileURL(for: song)) != nil {
            prepareBackgroundStemPlaybackIfPossible(for: song)
            return
        }

        let songID = song.id

        let sourceURL = localPlaybackFileURL(for: song)

        if let sourceURL {
            cancelBackgroundAnalysisRetry()
            DebugLogger.log("Triggering background analysis for \(songID)", category: .ai)
            VocalSeparator.shared.analyzeInBackground(songID: songID, sourceURL: sourceURL)
        } else {
            DebugLogger.log(
                "Source not available yet for background analysis of \(songID), will retry",
                category: .ai
            )
            cancelBackgroundAnalysisRetry()
            let generation = backgroundAnalysisRetryGeneration
            backgroundAnalysisRetryTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
                guard let self,
                      generation == backgroundAnalysisRetryGeneration,
                      !Task.isCancelled,
                      let currentSong,
                      currentSong.id == songID,
                      aiAutoAnalyze,
                      aiEnabled
                else { return }
                guard !anyAIEffectActive else { return }
                backgroundAnalysisRetryTask = nil
                triggerBackgroundAnalysis(for: currentSong)
            }
        }
    }

    private func applyMLSeparationIfNeeded() {
        instrumentalTask?.cancel()
        instrumentalTask = nil
        separationGeneration &+= 1
        let gen = separationGeneration
        guard aiEnabled, !isRadioMode, let song = currentSong else {
            VocalSeparator.shared.cancel()
            preparedStemSongID = nil
            revertAIPlaybackToMain()
            if aiEnabled, aiAutoAnalyze, !isRadioMode, let song = currentSong {
                triggerBackgroundAnalysis(for: song)
            }
            return
        }
        guard VocalSeparator.shared.isAvailable else {
            preparedStemSongID = nil
            revertAIPlaybackToMain()
            return
        }
        let shouldKeepPreparedStems = keepPreparedStems(for: song)
        guard anyAIEffectActive || shouldKeepPreparedStems else {
            VocalSeparator.shared.cancel()
            revertAIPlaybackToMain()
            if aiAutoAnalyze {
                triggerBackgroundAnalysis(for: song)
            }
            return
        }
        if shouldKeepPreparedStems, !anyAIEffectActive {
            revertAIPlaybackToMain()
            triggerBackgroundAnalysis(for: song)
            return
        }
        cancelBackgroundAnalysisRetry()
        if anyAIEffectActive {
            VocalSeparator.shared.cancelBackgroundAnalysis()
        }
        if avEngine.mode == .aiStems {
            applyAIMixVolumes()
            return
        }
        if let sourceURL = localPlaybackFileURL(for: song),
           let stems = cachedStems(for: song, sourceURL: sourceURL)
        {
            DebugLogger.log("Using cached stems for \(song.id)", category: .ai)
            preparedStemSongID = song.id
            switchActivePlaybackToStems(
                for: song, stems: stems, sourceURL: sourceURL,
                onReady: { [weak self] in self?.applyAIMixVolumes() }
            )
            return
        }
        guard anyAIEffectActive else {
            triggerBackgroundAnalysis(for: song)
            return
        }
        VocalSeparator.shared.cancel()
        let songID = song.id
        let initialStart = activePlaybackTime(for: song)
        let totalDur = isStreamMode ? Double(song.duration) : avEngine.duration
        if totalDur.isFinite, totalDur > 0, initialStart >= totalDur - 1.0 {
            return
        }
        DebugLogger.log(
            "Starting real-time separation for \(songID) from \(initialStart)s",
            category: .separation
        )
        instrumentalTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let activeSong = currentSong, activeSong.id == songID else { return }
            var sourceURL = localPlaybackFileURL(for: activeSong)
            let deadline = Date().addingTimeInterval(30)
            while sourceURL == nil, Date() < deadline {
                if Task.isCancelled { return }
                guard separationGeneration == gen,
                      let currentSong = self.currentSong,
                      currentSong.id == songID,
                      anyAIEffectActive
                else { return }
                sourceURL = localPlaybackFileURL(for: currentSong)
                if sourceURL == nil {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            guard let sourceURL else { return }
            if Task.isCancelled { return }
            guard separationGeneration == gen,
                  let currentSong,
                  currentSong.id == songID,
                  anyAIEffectActive
            else { return }

            do {
                let separationStart = max(initialStart, activePlaybackTime(for: currentSong))
                let stems = try await VocalSeparator.shared.separateRealTime(
                    forSongID: songID, sourceURL: sourceURL, fromTime: separationStart
                )
                if Task.isCancelled {
                    stems.temporaryLease?.cleanup()
                    return
                }
                guard separationGeneration == gen,
                      self.currentSong?.id == songID, anyAIEffectActive
                else {
                    stems.temporaryLease?.cleanup()
                    return
                }
                switchActivePlaybackToStems(
                    for: song, stems: stems, sourceURL: sourceURL,
                    onReady: { [weak self] in self?.applyAIMixVolumes() }
                )
                DebugLogger.log(
                    "Separation applied for \(songID), mode=realtime",
                    category: .separation
                )
            } catch is CancellationError {
                return
            } catch VocalSeparatorError.cancelled {
                return
            } catch VocalSeparatorError.unavailable {
                return
            } catch {
                DebugLogger.log("AI separation failed for \(songID): \(error)", category: .separation)
                return
            }
        }
    }

    private func configureAudioSessionCategory() {
        do {
            if #available(iOS 13.0, *) {
                try AVAudioSession.sharedInstance().setCategory(
                    .playback, mode: .default, policy: .longFormAudio, options: []
                )
            } else {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            }
        } catch {}
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(true, options: [.notifyOthersOnDeactivation])
    }

    private func recoverFromEngineConfigChange() {
        guard isPlaying, !isRadioMode, !isStreamMode else { return }
        let position = lastKnownPlaybackTime
        DebugLogger.log(
            "Recovering playback after engine config change at \(position)s",
            category: .playback
        )
        configureAudioSessionCategory()
        activateAudioSession()
        avEngine.startEngineIfNeeded()
        avEngine.seek(to: position)
    }

    private func handleMediaServicesReset() {
        DebugLogger.log("Media services were reset — reconfiguring audio", category: .playback)
        configureAudioSessionCategory()
        activateAudioSession()
        if isPlaying, !isRadioMode, !isStreamMode {
            let position = lastKnownPlaybackTime
            avEngine.startEngineIfNeeded()
            avEngine.seek(to: position)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaybackRequested
            DebugLogger.log(
                "Audio session interruption began; should resume later=\(wasPlayingBeforeInterruption)",
                category: .playback
            )
            if wasPlayingBeforeInterruption {
                handlingAudioSessionInterruption = true
                pauseCurrentPlayback(source: "audioSessionInterruptionBegan")
                handlingAudioSessionInterruption = false
            }
        case .ended:
            guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else {
                wasPlayingBeforeInterruption = false
                return
            }
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
            DebugLogger.log(
                "Audio session interruption ended; system wants resume=\(opts.contains(.shouldResume)), app wants resume=\(wasPlayingBeforeInterruption)",
                category: .playback
            )
            if opts.contains(.shouldResume), wasPlayingBeforeInterruption {
                resumeCurrentPlayback(source: "audioSessionInterruptionEnded")
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            wasPlayingBeforeInterruption = false
        }
    }

    private func handleRouteChange(_ note: Notification) {
        updateRouteIcon()
        guard let info = note.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }
        if reason == .oldDeviceUnavailable, isPlaybackRequested {
            pauseCurrentPlayback(source: "routeChange.oldDeviceUnavailable")
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
        func performOnMain(
            _ action: @escaping @MainActor () -> MPRemoteCommandHandlerStatus
        ) -> MPRemoteCommandHandlerStatus {
            if Thread.isMainThread {
                return MainActor.assumeIsolated { action() }
            }
            // MediaPlayer can deliver remote-command callbacks off the main thread.
            // Return only after the playback state and Now Playing info have changed;
            // returning .success before the main actor update lets Control Center redraw
            // from stale state and can leave the play/pause button out of sync.
            // Apple documents the public integration path as MPRemoteCommandCenter
            // handlers plus MPNowPlayingInfoCenter metadata/rate updates:
            // https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MediaPlaybackGuide/Contents/Resources/en.lproj/RefiningTheUserExperience/RefiningTheUserExperience.html
            var status: MPRemoteCommandHandlerStatus = .commandFailed
            DispatchQueue.main.sync {
                status = MainActor.assumeIsolated { action() }
            }
            return status
        }

        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.removeTarget(nil)
        cc.changePlaybackPositionCommand.removeTarget(nil)

        cc.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                DebugLogger.log("Remote play command received", category: .playback)
                if self.isPlaybackRequested {
                    self.updateNowPlayingInfo(reloadArtwork: false)
                    return .success
                }
                return self.resumeCurrentPlayback(source: "remote.play") ? .success : .commandFailed
            }
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                DebugLogger.log("Remote pause command received", category: .playback)
                if !self.isPlaybackRequested {
                    // Some iOS surfaces can send pauseCommand from a stale paused
                    // visual state even when the user is pressing the center play
                    // button. Treat that stale pause as resume; removing this
                    // fallback made lock-screen/control state diverge in device
                    // testing, so this intentionally preserves the working
                    // system-integration behavior over strict command semantics.
                    return self.resumeCurrentPlayback(source: "remote.pauseAsPlay") ? .success : .commandFailed
                }
                return self.pauseCurrentPlayback(source: "remote.pause") ? .success : .commandFailed
            }
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                DebugLogger.log("Remote toggle command received", category: .playback)
                return self.togglePlayPause(source: "remote.toggle") ? .success : .commandFailed
            }
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                DebugLogger.log("Remote next command received", category: .playback)
                self.playNextOrRandom()
                return .success
            }
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                DebugLogger.log("Remote previous command received", category: .playback)
                self.playPrevious()
                return .success
            }
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent,
                  positionEvent.positionTime.isFinite
            else { return .commandFailed }
            return performOnMain {
                let dur = self.playbackDuration
                guard dur.isFinite, dur > 0 else { return .commandFailed }
                DebugLogger.log(
                    "Remote seek command received: \(positionEvent.positionTime)",
                    category: .playback
                )
                self.seek(to: positionEvent.positionTime / dur)
                return .success
            }
        }
        updateRemoteCommandAvailability()
    }

    private func updateRemoteCommandAvailability() {
        let cc = MPRemoteCommandCenter.shared()
        let hasCurrentItem = currentSong != nil
        cc.playCommand.isEnabled = hasCurrentItem
        cc.pauseCommand.isEnabled = hasCurrentItem
        cc.togglePlayPauseCommand.isEnabled = hasCurrentItem
        cc.nextTrackCommand.isEnabled = hasCurrentItem && !isRadioMode
        cc.previousTrackCommand.isEnabled = hasCurrentItem && !isRadioMode
        cc.changePlaybackPositionCommand.isEnabled = hasCurrentItem && !isRadioMode
        DebugLogger.log(
            "Remote commands availability: item=\(hasCurrentItem), play=\(cc.playCommand.isEnabled), pause=\(cc.pauseCommand.isEnabled), toggle=\(cc.togglePlayPauseCommand.isEnabled), requested=\(isPlaybackRequested)",
            category: .playback
        )
    }

    private func updateNowPlayingInfo(reloadArtwork: Bool) {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            lastNowPlayingElapsedSecond = nil
            lastNowPlayingPlaybackRate = nil
            lastLoggedNowPlayingElapsedSecond = nil
            updateRemoteCommandAvailability()
            return
        }
        let targetArt = isRadioMode ? radioArtworkURL : song.imageURL
        let shouldReloadArtwork = reloadArtwork || artworkURL != targetArt
        let info = makeNowPlayingInfo(
            for: song,
            elapsed: isRadioMode ? nil : playbackTime,
            includeExistingArtwork: !shouldReloadArtwork
        )
        if shouldReloadArtwork {
            artworkURL = targetArt
            #if canImport(UIKit)
                if reloadArtwork { nowPlayingArtwork = nil }
            #endif
            warmPlayerArtwork(for: song)
            if let targetArt {
                loadArtworkAsync(from: targetArt)
            }
        }
        if shouldResetNowPlayingIdentity {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommandAvailability()
        DebugLogger.log(
            "Now Playing updated: rate=\(nowPlayingPlaybackRate), playing=\(isPlaying), buffering=\(isBuffering)",
            category: .playback
        )
        lastNowPlayingElapsedSecond = isRadioMode ? nil : Int(playbackTime.rounded(.down))
        lastNowPlayingPlaybackRate = nowPlayingPlaybackRate
        lastLoggedNowPlayingElapsedSecond = nil
    }

    private var shouldResetNowPlayingIdentity: Bool {
        guard isStreamMode || isRadioMode else { return false }
        guard let lastNowPlayingPlaybackRate else { return false }
        return lastNowPlayingPlaybackRate != nowPlayingPlaybackRate
    }

    private func updateNowPlayingElapsed(_ elapsed: Double) {
        guard isPlaying else {
            updateNowPlayingInfo(reloadArtwork: false)
            return
        }
        let roundedSecond = Int(elapsed.rounded(.down))
        let playbackRate = nowPlayingPlaybackRate
        guard roundedSecond != lastNowPlayingElapsedSecond
            || playbackRate != lastNowPlayingPlaybackRate else { return }
        guard let song = currentSong else {
            updateNowPlayingInfo(reloadArtwork: false)
            return
        }
        let info = makeNowPlayingInfo(
            for: song,
            elapsed: isRadioMode ? nil : elapsed,
            includeExistingArtwork: true
        )
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if lastLoggedNowPlayingElapsedSecond == nil
            || roundedSecond - (lastLoggedNowPlayingElapsedSecond ?? 0) >= 15
        {
            DebugLogger.log(
                "Now Playing elapsed update: elapsed=\(elapsed), rate=\(playbackRate)",
                category: .playback
            )
            lastLoggedNowPlayingElapsedSecond = roundedSecond
        }
        lastNowPlayingElapsedSecond = roundedSecond
        lastNowPlayingPlaybackRate = playbackRate
    }

    private func makeNowPlayingInfo(
        for song: Song,
        elapsed: TimeInterval?,
        includeExistingArtwork: Bool
    ) -> [String: Any] {
        let currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        // Keep system surfaces driven by the public Now Playing contract:
        // metadata, elapsed time, duration, and playback rate.
        let originalArtists = song.originalArtists?
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let artist: String
        if let originalArtists, !originalArtists.isEmpty {
            artist = originalArtists
        } else {
            artist = song.artistName
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyMediaType: MPMediaType.music.rawValue,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: nowPlayingPlaybackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if includeExistingArtwork,
           let artwork = currentInfo?[MPMediaItemPropertyArtwork]
        {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if isRadioMode {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        } else {
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
            info[MPMediaItemPropertyPlaybackDuration] = playbackDuration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed ?? playbackTime
        }
        return info
    }

    private func loadArtworkAsync(from url: URL) {
        let songID = currentSong?.id
        artworkTask?.cancel()
        artworkTask = nil
        artworkProcessingTask?.cancel()
        artworkProcessingTask = nil
        #if canImport(UIKit)
            if let cached = AudioPlayerManager.artworkCache.object(forKey: url as NSURL) {
                applyArtwork(cached, for: songID, artworkURL: url)
                return
            }
            artworkTask = SDWebImageManager.shared.loadImage(
                with: url,
                options: [],
                context: ImageCacheConfig.memoryAndDiskCacheContext,
                progress: nil
            ) { [weak self] image, _, _, _, _, _ in
                guard let self, currentSong?.id == songID else { return }
                guard let image else { return }
                // Square-cropping and downscaling redraw the full bitmap;
                // keep that work off the main thread. NSCache is thread-safe.
                artworkProcessingTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard !Task.isCancelled else { return }
                    let squareImage = image.croppedToSquare().downscaled(
                        maxPixel: AudioPlayerManager.artworkMaxPixel
                    )
                    guard !Task.isCancelled else { return }
                    let cost = Int(
                        squareImage.size.width * squareImage.size.height * squareImage.scale
                            * squareImage.scale * 4
                    )
                    AudioPlayerManager.artworkCache.setObject(
                        squareImage, forKey: url as NSURL, cost: cost
                    )
                    await MainActor.run { [weak self] in
                        self?.applyArtwork(squareImage, for: songID, artworkURL: url)
                    }
                }
            }
        #endif
    }

    #if canImport(UIKit)
        private func applyArtwork(_ image: UIImage, for songID: String?, artworkURL requestedURL: URL) {
            // The system may call the artwork request handler off the main
            // thread; @Sendable keeps it from inheriting main-actor isolation.
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let song = self.currentSong,
                      song.id == songID,
                      self.artworkURL == requestedURL
                else { return }
                var info = self.makeNowPlayingInfo(
                    for: song,
                    elapsed: self.isRadioMode ? nil : self.playbackTime,
                    includeExistingArtwork: false
                )
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                self.updateRemoteCommandAvailability()
                if self.isRadioMode {
                    self.lastNowPlayingElapsedSecond = nil
                } else {
                    self.lastNowPlayingElapsedSecond = Int(self.playbackTime.rounded(.down))
                }
                self.lastNowPlayingPlaybackRate = self.nowPlayingPlaybackRate
                self.lastLoggedNowPlayingElapsedSecond = nil
                self.nowPlayingArtwork = image
            }
        }
    #endif

    #if canImport(UIKit)
        private func beginTrackTransitionBackgroundTask() {
            endTrackTransitionBackgroundTask()
            trackTransitionTaskID = UIApplication.shared.beginBackgroundTask(
                withName: "TrackTransition"
            ) { [weak self] in
                guard let self else { return }
                if trackTransitionTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(trackTransitionTaskID)
                    trackTransitionTaskID = .invalid
                }
            }
        }

        private func endTrackTransitionBackgroundTask() {
            guard trackTransitionTaskID != .invalid else { return }
            UIApplication.shared.endBackgroundTask(trackTransitionTaskID)
            trackTransitionTaskID = .invalid
        }
    #endif

    private func checkEasterEgg(for song: Song) {
        resetEasterEggWork()

        guard !isRadioMode else { return }
        if song.id == easterEggSongID { return }
        // Shared with cover-art/captcha eggs: 1/1000 normally, or always when
        // developer mode has "Always Trigger" enabled. The old `nk.easterEggEnabled`
        // key was never written by any UI, so the track egg was effectively dead.
        guard DeveloperMode.shouldTriggerEasterEgg() else { return }

        if containsCJKIdeograph(song.title) {
            queueEasterEggSong()
            return
        }

        easterEggLyricsTask = Task { [weak self] in
            guard let self else { return }
            let lyrics = await self.fetchLyricsForEasterEgg(songID: song.id)
            guard !Task.isCancelled, let lyrics else { return }
            let hasCJK = lyrics.contains { self.containsCJKIdeograph($0.text) }
            guard hasCJK else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.currentSong?.id == song.id else { return }
                self.queueEasterEggSong()
            }
        }
    }

    private func resetEasterEggWork() {
        easterEggQueuedForCurrentSong = false
        easterEggLyricsTask?.cancel()
        easterEggLyricsTask = nil
        easterEggSongTask?.cancel()
        easterEggSongTask = nil
    }

    /// Detects CJK ideographs (and Bopomofo). Shared ranges cover Chinese hanzi
    /// and Japanese kanji; that matches the intended easter-egg trigger.
    private func containsCJKIdeograph(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value) ||
            (0x2A700...0x2B73F).contains(scalar.value) ||
            (0x2B740...0x2B81F).contains(scalar.value) ||
            (0x2B820...0x2CEAF).contains(scalar.value) ||
            (0x2F800...0x2FA1F).contains(scalar.value) ||
            (0x3100...0x312F).contains(scalar.value)
        }
    }

    private func fetchLyricsForEasterEgg(songID: String) async -> [LyricLine]? {
        if let cached = LyricsCacheStore.load(songID: songID, variant: .translated) {
            return cached
        }
        if let cached = LyricsCacheStore.load(songID: songID, variant: .original) {
            return cached
        }
        let encoded = songID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? songID
        guard let url = URL(string: "\(StorageHost.api)/api/songs/\(encoded)/lyrics") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        GuestIdentity.applyIfNeeded(to: &request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return nil }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            guard let raw = try? JSONDecoder().decode([RawLyricLine].self, from: data) else { return nil }
            let parsed = raw.compactMap { line -> LyricLine? in
                guard let time = TimeSpanParser.parse(line.time) else { return nil }
                return LyricLine(time: time, text: line.text)
            }
            if !parsed.isEmpty {
                LyricsCacheStore.save(parsed, songID: songID, variant: .original)
            }
            return parsed
        } catch {
            return nil
        }
    }

    private func queueEasterEggSong() {
        guard !easterEggQueuedForCurrentSong else { return }
        easterEggQueuedForCurrentSong = true
        let triggeringSongID = currentSong?.id
        DebugLogger.log("Easter egg triggered — fetching song \(easterEggSongID)", category: .playback)
        easterEggSongTask?.cancel()
        easterEggSongTask = Task { [weak self] in
            guard let self else { return }
            do {
                let song = try await KaraokeAPIClient.fetchSong(id: self.easterEggSongID)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.easterEggSongTask = nil
                    guard self.currentSong?.id == triggeringSongID else { return }
                    guard self.currentSong?.id != song.id else { return }
                    self.playNext(song: song)
                    DebugLogger.log("Easter egg song queued as next: \(song.title)", category: .playback)
                }
            } catch {
                guard !Task.isCancelled else { return }
                DebugLogger.log("Easter egg: failed to fetch song — \(error)", category: .playback)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.easterEggQueuedForCurrentSong = false
                    self.easterEggSongTask = nil
                }
            }
        }
    }

    private func fetchRandomTrending() {
        guard let triggeringSongID = currentSong?.id else {
            #if canImport(UIKit)
                endTrackTransitionBackgroundTask()
            #endif
            return
        }
        let loadToken = autoplayFetchOwnership.begin()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let songs = try await KaraokeAPIClient.trendingSongs(days: 7, take: 50)
                guard autoplayFetchOwnership.finish(loadToken) else { return }
                autoplayFetchTask = nil
                guard !Task.isCancelled,
                      currentSong?.id == triggeringSongID,
                      autoplayEnabled,
                      repeatMode == .off,
                      !isRadioMode,
                      let random = songs.randomElement()
                else {
                    #if canImport(UIKit)
                        endTrackTransitionBackgroundTask()
                    #endif
                    return
                }
                let rotatedQueue: [Song] = if let index = songs.firstIndex(of: random) {
                    Array(songs[index...]) + Array(songs[..<index])
                } else {
                    songs
                }
                play(song: random, context: rotatedQueue)
            } catch {
                guard autoplayFetchOwnership.finish(loadToken) else { return }
                autoplayFetchTask = nil
                #if canImport(UIKit)
                    endTrackTransitionBackgroundTask()
                #endif
            }
        }
        autoplayFetchTask = task
    }

    private func reportPlayCount(for songID: String) {
        Task {
            guard var req = try? KaraokeAPIClient.request(
                path: "/api/songs/playCount/\(songID)"
            ) else { return }
            req.httpMethod = "PUT"
            let _ = try? await KaraokeAPIClient.data(for: req)
        }
    }

    private func enrichSongMetadataIfNeeded(for song: Song) {
        guard !song.hasArtistMetadata else { return }
        let songID = song.id
        Task { [weak self] in
            guard let self else { return }
            let body: [String: Any] = ["page": 1, "pageSize": 1, "search": song.title]
            if let req = try? KaraokeAPIClient.jsonRequest(path: "/api/songs", body: body),
               let data = try? await KaraokeAPIClient.data(for: req)
            {
                self.applyEnrichedMetadata(from: data, songID: songID)
                return
            }
            guard let req = try? KaraokeAPIClient.request(
                path: "/api/explore/trendings",
                queryItems: [URLQueryItem(name: "days", value: "all")]
            ),
                  let data = try? await KaraokeAPIClient.data(for: req)
            else { return }
            self.applyEnrichedMetadata(from: data, songID: songID)
        }
    }

    private func applyEnrichedMetadata(from data: Data, songID: String) {
        if let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
           let match = response.items.first(where: { $0.id == songID }),
           currentSong?.id == songID
        {
            currentSong = match
            updateNowPlayingInfo(reloadArtwork: false)
            return
        }
        if let songs = try? JSONDecoder().decode([Song].self, from: data),
           let match = songs.first(where: { $0.id == songID }),
           currentSong?.id == songID
        {
            currentSong = match
            updateNowPlayingInfo(reloadArtwork: false)
        }
    }

    private func handleTransitionBegin(plan: TransitionCoordinator.TransitionPlan) {
        #if canImport(UIKit)
            beginTrackTransitionBackgroundTask()
        #endif
        activeCrossfadePlan = plan
        configureAudioSessionCategory()
        activateAudioSession()
        DebugLogger.log(
            "Transition begin next=\(plan.nextSong.id), file=\(plan.nextFileURL.lastPathComponent), fade=\(plan.fadeDuration), ramp=\(plan.rampStyle), streamMode=\(isStreamMode), aiEffectActive=\(anyAIEffectActive)",
            category: .playback
        )

        if anyAIEffectActive {
            quickCutToNext(plan: plan)
        } else {
            avEngine.beginCrossfade(
                url: plan.nextFileURL,
                duration: plan.fadeDuration,
                ramp: plan.rampStyle
            )
            let timeout = plan.fadeDuration + 3.0
            transitionTimeoutGeneration &+= 1
            let timeoutGeneration = transitionTimeoutGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self,
                      transitionTimeoutGeneration == timeoutGeneration,
                      transitionCoordinator.state.isCrossfading
                else { return }
                let handoffReady = avEngine.currentURL?.path == plan.nextFileURL.path && avEngine.isPlaying
                DebugLogger.log(
                    "Transition timeout fallback fired for next=\(plan.nextSong.id), currentSong=\(currentSong?.id ?? "nil"), audioURL=\(avEngine.currentURL?.lastPathComponent ?? "nil"), expected=\(plan.nextFileURL.lastPathComponent), audioTime=\(avEngine.currentTime), isPlaying=\(isPlaying), handoffReady=\(handoffReady)",
                    category: .playback
                )
                if handoffReady {
                    transitionCoordinatorDidFinish()
                } else {
                    DebugLogger.log(
                        "Transition timeout recovery forcing play(\(plan.nextSong.id))",
                        category: .playback
                    )
                    play(
                        song: plan.nextSong,
                        queueIndex: plan.nextQueueIndex,
                        resetTransitionVolume: true
                    )
                }
            }
        }
    }

    private func quickCutToNext(plan: TransitionCoordinator.TransitionPlan) {
        DebugLogger.log(
            "Quick cut transition start next=\(plan.nextSong.id), fade=\(plan.fadeDuration)",
            category: .playback
        )
        cancelQuickCutTimer(resetVolume: false)
        instrumentalTask?.cancel()
        instrumentalTask = nil
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        let generation = quickCutCompletionGate.begin()
        let fadeDuration = plan.fadeDuration.isFinite ? max(0, plan.fadeDuration) : 0
        let interval = AVEnginePlayback.transitionTimerInterval
        if fadeDuration <= interval {
            avEngine.setMasterVolume(0)
            completeQuickCut(generation, plan: plan)
            return
        }
        let steps = max(1, Int((fadeDuration / interval).rounded(.up)))
        let counter = TimerStepCounter()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            let finished = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return true }
                guard self.quickCutCompletionGate.owns(generation) else { return true }
                guard self.transitionCoordinator.state.isCrossfading, !self.isRadioMode else {
                    self.cancelPendingTransitionWork()
                    return true
                }
                counter.step += 1
                let t = min(1, Float(counter.step) / Float(max(1, steps)))
                self.avEngine.setMasterVolume(1 - t)
                return t >= 1 ? self.completeQuickCut(generation, plan: plan) : false
            }
            if finished { timer.invalidate() }
        }
        quickCutTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        quickCutFallbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(fadeDuration + interval))
            } catch {
                return
            }
            self?.completeQuickCut(generation, plan: plan)
        }
    }

    @discardableResult
    private func completeQuickCut(
        _ generation: UInt64,
        plan: TransitionCoordinator.TransitionPlan
    ) -> Bool {
        guard quickCutCompletionGate.consume(generation) else { return false }
        quickCutTimer?.invalidate()
        quickCutTimer = nil
        quickCutFallbackTask?.cancel()
        quickCutFallbackTask = nil
        guard transitionCoordinator.state.isCrossfading, !isRadioMode else {
            cancelPendingTransitionWork()
            return true
        }
        DebugLogger.log(
            "Quick cut transition complete -> play(\(plan.nextSong.id))",
            category: .playback
        )
        activeCrossfadePlan = nil
        transitionCoordinator.reset()
        avEngine.setMasterVolume(0)
        play(
            song: plan.nextSong,
            queueIndex: plan.nextQueueIndex,
            resetTransitionVolume: false
        )
        avEngine.setMasterVolume(1)
        return true
    }

    private func transitionCoordinatorDidFinish() {
        let plan: TransitionCoordinator.TransitionPlan
        if case let .crossfading(currentPlan) = transitionCoordinator.state {
            plan = currentPlan
        } else if let retainedPlan = activeCrossfadePlan {
            plan = retainedPlan
            DebugLogger.log(
                "Completing retained crossfade plan for \(retainedPlan.nextSong.id) after coordinator reset",
                category: .playback
            )
        } else {
            transitionCoordinator.reset()
            return
        }
        let handoffReady = avEngine.currentURL?.path == plan.nextFileURL.path
        let handoffDuration = avEngine.duration
        let hasPlayableDuration = handoffDuration.isFinite && handoffDuration > 0.1
        guard handoffReady, avEngine.isPlaying, hasPlayableDuration else {
            DebugLogger.log(
                "Transition completion recovery next=\(plan.nextSong.id), audioURL=\(avEngine.currentURL?.lastPathComponent ?? "nil"), expected=\(plan.nextFileURL.lastPathComponent), duration=\(handoffDuration), playing=\(avEngine.isPlaying)",
                category: .playback
            )
            activeCrossfadePlan = nil
            play(
                song: plan.nextSong,
                queueIndex: plan.nextQueueIndex,
                resetTransitionVolume: true
            )
            return
        }
        stopStreamPlayer()
        clearPreferredStreamResumeTime()
        let song = plan.nextSong
        currentPlaybackURL = plan.nextFileURL
        CacheManager.shared.recordAccess(for: plan.nextFileURL)
        reportPlayCount(for: song.id)
        enrichSongMetadataIfNeeded(for: song)
        deferredAIEffect = nil
        preparedStemSongID = nil
        let didAdvanceQueueOccurrence = currentQueueIndex != plan.nextQueueIndex
        setCurrentQueueIndex(plan.nextQueueIndex, matching: song)
        if currentSong?.id != song.id || didAdvanceQueueOccurrence {
            progress = 0
            var excludeIDs = activeSongIDs()
            excludeIDs.insert(song.id)
            scheduleIdleCacheCompression(excluding: excludeIDs)
            withAnimation(.easeInOut(duration: 0.32)) {
                currentSong = song
            }
        } else {
            currentSong = song
        }
        upcomingSong = nil
        checkEasterEgg(for: song)
        setPlaybackState(
            playing: true,
            buffering: false,
            reason: "transitionCoordinatorDidFinish"
        )
        DebugLogger.log(
            "Transition complete next=\(song.id), audioURL=\(avEngine.currentURL?.lastPathComponent ?? "nil"), time=\(avEngine.currentTime), duration=\(avEngine.duration), playing=\(avEngine.isPlaying)",
            category: .playback
        )
        updateNowPlayingInfo(reloadArtwork: true)
        // AVAudioPlayerNode may report the outgoing schedule completion after
        // stop() returns. Keep that stale callback suppressed past the point
        // where the transition plan and coordinator state are cleared.
        suppressPlaybackEndedCallbacks()
        activeCrossfadePlan = nil
        transitionCoordinator.reset()
        let protectedIDs = activeSongIDs()
        CacheManager.shared.enforceMusicCacheLimits(excluding: protectedIDs)
        if anyAIEffectActive {
            applyMLSeparationIfNeeded()
        } else if aiEnabled, aiAutoAnalyze, !isRadioMode {
            triggerBackgroundAnalysis(for: song)
            prepareBackgroundStemPlaybackIfPossible(for: song)
        }
        #if canImport(UIKit)
            endTrackTransitionBackgroundTask()
        #endif
    }
}

#if canImport(UIKit)
    // nonisolated: cropping and re-rendering are thread-safe and run off the
    // main actor when preparing Now Playing artwork.
    nonisolated extension UIImage {
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
