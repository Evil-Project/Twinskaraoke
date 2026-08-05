import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import Observation

#if canImport(UIKit)
    import SDWebImage
    import UIKit
#endif

/// Tick counter for fade timers; only mutated on the main actor, but lives
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
@Observable
final class PlaybackClock {
    static let shared = PlaybackClock()

    var progress: Double = 0

    private init() {}
}

@MainActor
@Observable
final class AudioPlayerManager {
    static let shared = AudioPlayerManager()
    var currentSong: Song?
    var isPlaying = false
    var isBuffering = false

    var progress: Double {
        get { PlaybackClock.shared.progress }
        set { PlaybackClock.shared.progress = newValue }
    }

    var queue: [Song] = []
    var isEditingProgress = false
    var volume: Double = 1.0
    var isUserScrubbingVolume: Bool = false
    private var suppressTransitionAfterSeek = false
    private var preferredStreamResumeSongID: String?
    private var preferredStreamResumeTime: TimeInterval?
    private var deferredAIEffect: AudioEffect?
    var routeIcon: String = "airplayaudio"
    var routeName: String = ""
    var repeatMode: RepeatMode = .off
    var isShuffled: Bool = false
    var autoplayEnabled: Bool = true
    var isRadioMode: Bool = false
    var radioArtworkURL: URL?
    private var isStreamMode: Bool {
        streamPlayer != nil
    }

    var aiEnabled: Bool = {
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
                VocalSeparator.shared.cleanupRealtimeTemp()
                if avEngine.mode == .aiStems { avEngine.revertToMain() }
            }
        }
    }

    var aiAutoAnalyze: Bool = UserDefaults.standard.bool(forKey: "nk.aiAutoAnalyze") {
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
                if !anyAIEffectActive, avEngine.mode == .aiStems {
                    avEngine.revertToMain()
                }
            }
        }
    }

    var karaokeMode: Bool = false {
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

    var aiVocalStrength: Float = AudioPlayerManager.loadAIVocalStrength() {
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

    var bassEnhanceMode: Bool = false {
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

    var bassEnhanceStrength: Float = AudioPlayerManager.loadFloat(
        "nk.bassEnhanceStrength", default: 0.5
    ) {
        didSet {
            UserDefaults.standard.set(bassEnhanceStrength, forKey: "nk.bassEnhanceStrength")
            applyAIMixVolumes()
        }
    }

    var vocalEnhanceMode: Bool = false {
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

    var vocalEnhanceStrength: Float = AudioPlayerManager.loadFloat(
        "nk.vocalEnhanceStrength", default: 0.5
    ) {
        didSet {
            UserDefaults.standard.set(vocalEnhanceStrength, forKey: "nk.vocalEnhanceStrength")
            applyAIMixVolumes()
        }
    }

    var instrumentalEnhanceMode: Bool = false {
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

    var instrumentalEnhanceStrength: Float = AudioPlayerManager.loadFloat(
        "nk.instrumentalEnhanceStrength", default: 0.5
    ) {
        didSet {
            UserDefaults.standard.set(instrumentalEnhanceStrength, forKey: "nk.instrumentalEnhanceStrength")
            applyAIMixVolumes()
        }
    }

    var eqEnabled: Bool = UserDefaults.standard.bool(forKey: "nk.eqEnabled") {
        didSet {
            UserDefaults.standard.set(eqEnabled, forKey: "nk.eqEnabled")
            avEngine.setEQEnabled(eqEnabled)
        }
    }

    private var eqPresetIsApplying = false
    var eqPreset: EQPreset = {
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

    var eqGainsDB: [Float] = (UserDefaults.standard.array(forKey: "nk.eqGainsDB") as? [Float])
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

    var autoMixEnabled: Bool =
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

    var crossfadeEnabled: Bool =
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

    var crossfadeSeconds: Double = AudioPlayerManager.loadCrossfadeSeconds() {
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

    var upcomingSong: Song?
    private(set) var preparedStemSongID: String?
    #if canImport(UIKit)
        var nowPlayingArtwork: UIImage?
    #endif
    private var lastNowPlayingElapsedSecond: Int?
    private var lastNowPlayingPlaybackRate: Double?
    private var lastLoggedNowPlayingElapsedSecond: Int?
    private var lastRemoteCommandDiagnosticState: String?
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

    // Construct the graph only after init has configured/activated the audio
    // session, so its fixed effects bus adopts the active hardware sample rate.
    @ObservationIgnored private lazy var avEngine = AVEnginePlayback()
    private let transitionCoordinator = TransitionCoordinator()
    private var radioPlayer: AVPlayer?
    private var streamPlayer: AVPlayer?
    private var streamEndObserver: NSObjectProtocol?
    private var radioTimeObserver: (player: AVPlayer, token: Any)?
    private var radioPlayerCancellables = Set<AnyCancellable>()
    private var streamPlayerCancellables = Set<AnyCancellable>()
    private var radioPlaybackRequested = false
    private var streamPlaybackRequested = false
    @ObservationIgnored private var remotePlaybackCacheTask: Task<Void, Never>?
    private var remotePlaybackCacheToken: UUID?
    private var fetchRandomTrendingToken: UUID?
    private var cacheRecoverySongID: String?
    // Song IDs already sent through enrichSongMetadataIfNeeded this session;
    // repeat-one loops would otherwise re-issue the search + trending
    // fallback requests on every replay.
    private var enrichmentAttemptedSongIDs = Set<String>()
    private var lastKnownPlaybackTime: TimeInterval = 0
    private var pollTimer: Timer?
    // Volume ramps run on a background DispatchSourceTimer (like the engine
    // crossfade ramp) so they don't fire on RunLoop.main during scroll
    // tracking; per-tick work is dispatched back to the main actor.
    private nonisolated static let volumeRampQueue = DispatchQueue(
        label: "com.Mag1cByt3s.Twinskaraoke.volume-ramp",
        qos: .userInteractive
    )
    private var streamFadeTimer: DispatchSourceTimer?
    // Bumped whenever the fade timer is cancelled so a tick already dispatched
    // to the main actor by the background timer no-ops instead of applying a
    // stale volume step.
    private var streamFadeGeneration: UInt64 = 0
    private var streamStartedAt: Date?

    private var _suppressModeSwitch = false
    private var originalQueue: [Song] = []
    private var cancellables = Set<AnyCancellable>()
    private var artworkURL: URL?
    private var artworkTask: (any SDWebImageOperation)?
    @ObservationIgnored private var artworkProcessingTask: Task<Void, Never>?
    private var playerArtworkWarmupTasks: [String: any SDWebImageOperation] = [:]
    private var warmedPlayerArtworkAt: [String: Date] = [:]
    private var currentPlaybackURL: URL?
    @ObservationIgnored private var instrumentalTask: Task<Void, Never>?
    @ObservationIgnored private var preparedStemTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundAnalysisRetryTask: Task<Void, Never>?
    @ObservationIgnored private var cacheCompressionTask: Task<Void, Never>?
    // Set while a stem-switch load is in flight so its failure can drop the
    // broken stem cache. Must be cleared on every pause/stop/new-play path:
    // those bump the engine's suppression token, the load completion then
    // returns early before clearing this, and a stale ID would make a later
    // unrelated engine error delete a valid stem cache.
    private var aiStemSwitchInFlightSongID: String?
    // The isPlaybackRequested snapshot of the in-flight stem switch, so a
    // load failure for a paused switch can fall back without un-pausing.
    private var aiStemSwitchInFlightShouldResume = true
    private var quickCutTimer: DispatchSourceTimer?
    private var quickCutGeneration: UInt64 = 0
    private var separationGeneration: UInt64 = 0
    private var transitionTimeoutGeneration: UInt64 = 0
    private var transitionStartGeneration: UInt64 = 0
    @ObservationIgnored private var transitionStartTask: Task<Void, Never>?
    private var activeCrossfadePlan: TransitionCoordinator.TransitionPlan?
    private var suppressPlaybackEndedUntil: Date = .distantPast
    private var wasPlayingBeforeInterruption = false
    private var audioSessionCategoryConfigured = false
    private var audioSessionIsActive = false
    private var handlingAudioSessionInterruption = false

    private let easterEggSongID = "73376790-47d2-4c17-a7fc-88d11dccd2f0"
    private var easterEggQueuedForCurrentSong = false
    @ObservationIgnored private var easterEggLyricsTask: Task<Void, Never>?
    @ObservationIgnored private var easterEggSongTask: Task<Void, Never>?

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

    // Private so `shared` stays the only instance: the audio session and the
    // remote-command centre it configures are process-wide singletons.
    private init() {
        configureAudioSessionCategory()
        activateAudioSession()
        let cacheCleanupCutoff = Date()
        Task.detached(priority: .utility) {
            AudioCacheStore.cleanupLegacyArtifacts(createdBefore: cacheCleanupCutoff)
        }
        DebugLogger.log("AudioPlayerManager initializing", category: .playback)
        setupRemoteCommands()

        avEngine.onPlaybackEnded = { [weak self] in
            guard let self, !self.isRadioMode else { return }
            guard isPlaying else { return }
            guard !avEngine.isCrossfading, !avEngine.isCrossfadePending else { return }
            guard quickCutTimer == nil else { return }
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
            let failedStemSwitchShouldResume = aiStemSwitchInFlightShouldResume
            aiStemSwitchInFlightSongID = nil
            let pendingTransitionSong: Song? = if case let .crossfading(plan) = transitionCoordinator.state {
                plan.nextSong
            } else {
                nil
            }
            cancelPendingTransitionWork()
            if let pendingTransitionSong, !self.isRadioMode {
                DebugLogger.log(
                    "Recovering from transition playback error with direct play(\(pendingTransitionSong.id))",
                    category: .playback
                )
                play(song: pendingTransitionSong, resetTransitionVolume: true)
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
                fallBackToMainPlayback(
                    for: song,
                    startAt: lastKnownPlaybackTime,
                    resume: failedStemSwitchSongID != song.id || failedStemSwitchShouldResume
                )
                return
            }
            if let song = currentSong, !self.isRadioMode,
               let playbackURL = currentPlaybackURL,
               playbackURL.path.hasPrefix(AudioPlayerManager.audioCacheDir.path)
            {
                guard cacheRecoverySongID != song.id else {
                    DebugLogger.log(
                        "Remote cache retry exhausted for \(song.id)",
                        category: .playback
                    )
                    AudioCacheStore.removeSongCache(for: song.id)
                    currentPlaybackURL = nil
                    setPlaybackState(
                        playing: false,
                        buffering: false,
                        reason: "avEngine.cacheRetryExhausted"
                    )
                    return
                }
                cacheRecoverySongID = song.id
                DebugLogger.log(
                    "Removing broken cache and retrying from remote for \(song.id)",
                    category: .cache
                )
                AudioCacheStore.removeSongCache(for: song.id)
                currentPlaybackURL = nil
                play(
                    song: song,
                    context: [],
                    resetTransitionVolume: true,
                    preserveCacheRecoveryState: true
                )
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
        transitionCoordinator.onTransitionPrepared = { [weak self] plan in
            self?.schedulePreparedTransition(plan)
        }
        transitionCoordinator.onUpcomingSongDetermined = { [weak self] song in
            self?.upcomingSong = song
        }

        // The former `FallbackArtProvider.objectWillChange -> objectWillChange`
        // forwarding is gone: it existed only to invalidate views that derive
        // artwork URLs through `Song`, and `@Observable` has no blanket
        // invalidation. Those views now read `FallbackArtRevision.shared`
        // directly, which is both narrower and no longer re-renders every
        // observer of the player.
        // AVAudioSession posts these off the main thread (route changes are
        // documented as arriving on a secondary thread). Under Swift 6 these
        // sink closures are main-actor-isolated, so delivering them on the
        // posting thread traps. Hop to main first, as the watch and TV
        // AudioManagers already do for the same handlers.
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleInterruption(note) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleRouteChange(note) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .vocalSeparatorDidCacheStems)
            .sink { [weak self] note in
                guard let self, let songID = note.object as? String else { return }
                handleCachedStemsReady(songID: songID)
            }
            .store(in: &cancellables)
        updateRouteIcon()
        syncSystemVolume()
        AVAudioSession.sharedInstance().publisher(for: \.outputVolume)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sysVol in
                self?.syncSystemVolume(sysVol)
            }
            .store(in: &cancellables)
        // Posted by the audio daemon when the media server restarts; the
        // delivery thread is undocumented, so don't assume it is main.
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleMediaServicesReset() }
            .store(in: &cancellables)
        #if canImport(UIKit)
            NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
                .sink { [weak self] _ in self?.handleMemoryWarning() }
                .store(in: &cancellables)
        #endif
    }

    isolated deinit {
        // Teardown touches main-actor-bound state: the RunLoop.main poll timer,
        // the radio time observer, and the AVPlayer. `isolated deinit` runs the
        // body on the main actor rather than asserting that the last release
        // happened there, which `MainActor.assumeIsolated` would trap on.
        pollTimer?.invalidate()
        quickCutTimer?.cancel()
        streamFadeTimer?.cancel()
        transitionStartTask?.cancel()
        instrumentalTask?.cancel()
        preparedStemTask?.cancel()
        backgroundAnalysisRetryTask?.cancel()
        remotePlaybackCacheTask?.cancel()
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
                // Already on the main actor, so end the background task
                // directly instead of deferring it to a Task that could
                // outlive the deinit.
                UIApplication.shared.endBackgroundTask(transitionTaskID)
            }
        #endif
    }

    private func cancelBackgroundAnalysisRetry() {
        backgroundAnalysisRetryTask?.cancel()
        backgroundAnalysisRetryTask = nil
    }

    private func localPlaybackFileURL(for song: Song) -> URL? {
        if let downloaded = DownloadManager.shared.immediatelyPlayableURL(for: song) {
            return downloaded
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        return AudioCacheStore.immediatelyPlayableMainURL(
            for: song.id,
            expectedRemoteURL: song.audioURL,
            expectedDuration: expectedDuration
        )
    }

    /// Local file lookup for the tap-to-play path: never decompresses on the
    /// main thread. Compressed-only cache entries return nil here and are
    /// recovered off-main by the remote playback cache task (which hits the
    /// same cache and decompresses before playing, without re-downloading).
    private func immediateLocalPlaybackFileURL(for song: Song) -> URL? {
        localPlaybackFileURL(for: song)
    }

    private func cachedStems(for song: Song, sourceURL: URL? = nil) async -> CachedStems? {
        await VocalSeparator.shared.cachedStems(
            forSongID: song.id,
            expectedDuration: expectedStemDuration(for: song, sourceURL: sourceURL)
        )
    }

    /// Non-decompressing stem lookup for main-thread fast paths: returns nil
    /// when only the compressed cache exists so callers can defer the
    /// decompression to the async `cachedStems` path instead.
    private func immediatelyCachedStems(for song: Song, sourceURL: URL? = nil) -> CachedStems? {
        VocalSeparator.shared.immediatelyAvailableStems(
            forSongID: song.id,
            expectedDuration: expectedStemDuration(for: song, sourceURL: sourceURL)
        )
    }

    private func expectedStemDuration(for song: Song, sourceURL: URL?) -> TimeInterval? {
        if song.duration > 0 {
            return TimeInterval(song.duration)
        }
        if let sourceURL {
            let duration = AudioCacheStore.audioDuration(at: sourceURL)
            return duration.isFinite && duration > 1.0 ? duration : nil
        }
        return nil
    }

    private func activeSongIDs() -> Set<String> {
        var ids = Set<String>()
        if let id = currentSong?.id { ids.insert(id) }
        if let id = upcomingSong?.id { ids.insert(id) }
        if let current = currentSong, let idx = queue.firstIndex(where: { $0.id == current.id }),
           idx + 1 < queue.count
        {
            ids.insert(queue[idx + 1].id)
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
            let cachedDuration = AudioCacheStore.audioDuration(at: playbackURL)
            if AudioCacheStore.durationAppearsComplete(
                actualDuration: cachedDuration,
                expectedDuration: expectedDuration
            ) {
                DebugLogger.log(
                    "Keeping duration-validated cache after stale premature-end callback for \(song.id): cached=\(cachedDuration), expected=\(expectedDuration)",
                    category: .cache
                )
                return true
            } else {
                DebugLogger.log(
                    "Removing corroborated incomplete cache after premature end for \(song.id): cached=\(cachedDuration), expected=\(expectedDuration)",
                    category: .cache
                )
                AudioCacheStore.removeSongCache(for: song.id)
                currentPlaybackURL = nil
            }
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
        if avEngine.mode == .aiStems {
            avEngine.revertToMain()
        }
    }

    private func restoreDeferredAIEffectIfNeeded(for songID: String) {
        guard currentSong?.id == songID else { return }
        guard aiEnabled, aiAutoAnalyze, !isRadioMode, isKaraokePreparedForCurrentSong else { return }
        guard let effect = deferredAIEffect else { return }
        deferredAIEffect = nil
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
    }

    private func prepareBackgroundStemPlaybackIfPossible(for song: Song) {
        guard aiEnabled, aiAutoAnalyze, !isRadioMode else { return }
        guard let sourceURL = localPlaybackFileURL(for: song) else { return }
        preparedStemTask?.cancel()
        let gen = separationGeneration
        // Decompresses compressed stem caches off the main thread.
        preparedStemTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let stems = await cachedStems(for: song, sourceURL: sourceURL) else { return }
            guard separationGeneration == gen,
                  currentSong?.id == song.id, !isRadioMode
            else { return }

            preparedStemSongID = song.id
            guard anyAIEffectActive else { return }
            switchActivePlaybackToStems(
                for: song, stems: stems, sourceURL: sourceURL,
                onReady: { [weak self] in self?.applyAIMixVolumes() }
            )
        }
    }

    private func scheduleIdleCacheCompression(excluding songIDs: Set<String>) {
        cacheCompressionTask?.cancel()
        cacheCompressionTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            AudioCacheStore.compressIdleAssets(excluding: songIDs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                CacheManager.shared.refreshSizes()
            }
        }
    }

    private func switchActivePlaybackToStems(
        for song: Song, stems: CachedStems, sourceURL: URL,
        onReady: (() -> Void)? = nil
    ) {
        guard !isRadioMode else { return }
        suppressPlaybackEndedCallbacks()
        let shouldResume = isPlaybackRequested
        let startAt = activePlaybackTime(for: song)
        currentPlaybackURL = sourceURL
        aiStemSwitchInFlightSongID = song.id
        aiStemSwitchInFlightShouldResume = shouldResume
        configureAudioSessionCategory()
        activateAudioSession()
        if shouldResume {
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        }
        let readyBlock: () -> Void = { [weak self] in
            guard let self else { return }
            aiStemSwitchInFlightSongID = nil
            if !shouldResume { avEngine.pause() }
            onReady?()
            #if canImport(UIKit)
                endTrackTransitionBackgroundTask()
            #endif
        }
        if isStreamMode {
            stopStreamPlayer()
            avEngine.playStems(
                originalURL: sourceURL,
                vocalsURL: stems.vocals,
                instrumentsURL: stems.instruments,
                startOffset: stems.startOffset,
                startAt: startAt,
                onReady: readyBlock
            )
        } else {
            avEngine.switchToStems(
                vocalsURL: stems.vocals,
                instrumentsURL: stems.instruments,
                startOffset: stems.startOffset,
                onReady: readyBlock
            )
        }
        setPlaybackState(
            playing: shouldResume,
            buffering: false,
            reason: "switchToPreparedStems"
        )
    }

    private func cancelQuickCutTimer(resetVolume: Bool = true) {
        quickCutGeneration &+= 1
        quickCutTimer?.cancel()
        quickCutTimer = nil
        if resetVolume {
            avEngine.setMasterVolume(1.0)
        }
    }

    private func cancelPendingTransitionWork(resetVolume: Bool = true) {
        transitionTimeoutGeneration &+= 1
        transitionStartGeneration &+= 1
        transitionStartTask?.cancel()
        transitionStartTask = nil
        activeCrossfadePlan = nil
        cancelQuickCutTimer(resetVolume: resetVolume)
        avEngine.cancelCrossfade()
        streamFadeGeneration &+= 1
        streamFadeTimer?.cancel()
        streamFadeTimer = nil
        if resetVolume { streamPlayer?.volume = 1.0 }
        transitionCoordinator.reset()
        upcomingSong = nil
        cancelBackgroundAnalysisRetry()
        #if canImport(UIKit)
            endTrackTransitionBackgroundTask()
        #endif
    }

    private func schedulePreparedTransition(_ plan: TransitionCoordinator.TransitionPlan) {
        transitionStartGeneration &+= 1
        let generation = transitionStartGeneration
        transitionStartTask?.cancel()

        let remaining = max(0, playbackDuration - activePlaybackTime(for: currentSong))
        let delay = max(0, remaining - plan.fadeDuration)
        DebugLogger.log(
            "Scheduling transition deadline next=\(plan.nextSong.id), in=\(String(format: "%.3f", delay))s",
            category: .playback
        )

        transitionStartTask = Task { [weak self] in
            guard delay.isFinite else { return }
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }
            guard let self,
                  transitionStartGeneration == generation,
                  isPlaying,
                  currentSong?.id != plan.nextSong.id
            else { return }
            transitionStartTask = nil
            transitionCoordinator.beginPreparedTransition(plan)
        }
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
        preparedStemTask?.cancel()
        preparedStemTask = nil
        resetEasterEggWork()
        cancelBackgroundAnalysisRetry()
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        VocalSeparator.shared.cleanupRealtimeTemp()
        preparedStemSongID = nil
        if anyAIEffectActive {
            _suppressModeSwitch = true
            karaokeMode = false
            bassEnhanceMode = false
            vocalEnhanceMode = false
            instrumentalEnhanceMode = false
            _suppressModeSwitch = false
        }
        if avEngine.mode == .aiStems {
            avEngine.revertToMain()
        }
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
                        self.progress = newProgress
                    }
                    self.updateNowPlayingElapsed(t)

                    if self.repeatMode != .one {
                        self.transitionCoordinator.poll(
                            currentTime: t,
                            totalDuration: dur,
                            currentSong: self.currentSong,
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
                    self.progress = newProgress
                }
                self.updateNowPlayingElapsed(t)

                if self.repeatMode != .one {
                    self.transitionCoordinator.poll(
                        currentTime: t,
                        totalDuration: totalDur,
                        currentSong: self.currentSong,
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

    func play(song: Song, context: [Song] = []) {
        play(song: song, context: context, resetTransitionVolume: true)
    }

    private func play(
        song: Song,
        context: [Song] = [],
        resetTransitionVolume: Bool,
        preserveCacheRecoveryState: Bool = false,
        reportsPlayCount: Bool = true
    ) {
        if !preserveCacheRecoveryState {
            cacheRecoverySongID = nil
        }
        DebugLogger.log("Play requested: \(song.title) (id: \(song.id))", category: .playback)
        let previousSongID = currentSong?.id
        let effectToResume = currentActiveEffect ?? deferredAIEffect
        suppressPlaybackEndedCallbacks()
        clearPreferredStreamResumeTime()
        if isRadioMode { RadioController.shared.stop() }
        stopRadioPlayer()
        stopStreamPlayer()
        isRadioMode = false
        radioArtworkURL = nil
        cancelPendingTransitionWork(resetVolume: resetTransitionVolume)
        avEngine.cancelCrossfade()
        avEngine.stop()
        aiStemSwitchInFlightSongID = nil
        instrumentalTask?.cancel()
        instrumentalTask = nil
        preparedStemTask?.cancel()
        preparedStemTask = nil
        separationGeneration &+= 1
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        VocalSeparator.shared.cleanupRealtimeTemp()
        if reportsPlayCount {
            reportPlayCount(for: song.id)
        }
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
        currentSong = song
        warmPlayerArtwork(for: song)
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
            preparedStemTask?.cancel()
            preparedStemTask = nil
            separationGeneration &+= 1
            VocalSeparator.shared.cancel()
            preparedStemSongID = song.id
            currentPlaybackURL = fileURL
            configureAudioSessionCategory()
            activateAudioSession()
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
            avEngine.playStems(
                originalURL: fileURL,
                vocalsURL: stems.vocals, instrumentsURL: stems.instruments,
                startOffset: stems.startOffset,
                onReady: { [weak self] in
                    self?.applyAIMixVolumes()
                    #if canImport(UIKit)
                        self?.endTrackTransitionBackgroundTask()
                    #endif
                }
            )
            setPlaybackState(
                playing: true,
                buffering: false,
                reloadArtwork: true,
                reason: "play.cachedStems"
            )
            return
        }
        if let fileURL {
            startPlayingFile(fileURL, resetSeparation: false)
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
        startStreamPlayback(
            url: remoteURL,
            songID: song.id,
            expectedDuration: expectedDuration,
            resetSeparationOnCacheReady: false
        )
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

        func inserting(_ song: Song, into source: [Song], after current: Song) -> [Song] {
            var updated = source
            updated.removeAll { $0.id == song.id && $0.id != current.id }
            if updated.contains(where: { $0.id == current.id }) == false {
                updated.insert(current, at: 0)
            }
            guard song.id != current.id else { return updated }
            let currentIndex = updated.firstIndex(where: { $0.id == current.id }) ?? 0
            let insertIndex = min(currentIndex + 1, updated.count)
            updated.insert(song, at: insertIndex)
            return updated
        }

        queue = inserting(song, into: queue, after: current)
        if !originalQueue.isEmpty {
            originalQueue = inserting(song, into: originalQueue, after: current)
        }
        transitionCoordinator.reset()
        upcomingSong = nil
    }

    private func startPlayingFile(
        _ url: URL,
        startAt: TimeInterval = 0,
        resetSeparation: Bool = true
    ) {
        suppressPlaybackEndedCallbacks()
        stopRadioPlayer()
        stopStreamPlayer()
        instrumentalTask?.cancel()
        instrumentalTask = nil
        preparedStemTask?.cancel()
        preparedStemTask = nil
        if resetSeparation {
            separationGeneration &+= 1
            VocalSeparator.shared.cancel()
            VocalSeparator.shared.cleanupRealtimeTemp()
        }
        streamStartedAt = nil
        currentPlaybackURL = url
        aiStemSwitchInFlightSongID = nil
        configureAudioSessionCategory()
        activateAudioSession()
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        avEngine.play(url: url, startAt: max(0, startAt)) { [weak self] in
            #if canImport(UIKit)
                self?.endTrackTransitionBackgroundTask()
            #endif
        }
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

    private func fallBackToMainPlayback(for song: Song, startAt: TimeInterval, resume: Bool = true) {
        suppressPlaybackEndedCallbacks()
        stopRadioPlayer()
        stopStreamPlayer()
        avEngine.stop()
        aiStemSwitchInFlightSongID = nil
        separationGeneration &+= 1
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        VocalSeparator.shared.cleanupRealtimeTemp()
        if avEngine.mode == .aiStems {
            avEngine.revertToMain()
        }
        let resumeAt = max(0, startAt.isFinite ? startAt : 0)
        guard resume else {
            // A paused stem switch whose stem load failed must not un-pause:
            // leave the deck unloaded and keep the position so the next
            // explicit resume reloads the main file at the same spot.
            lastKnownPlaybackTime = resumeAt
            setPlaybackState(
                playing: false,
                buffering: false,
                reason: "fallBackToMainPlayback.paused"
            )
            return
        }
        if let fileURL = localPlaybackFileURL(for: song) {
            startPlayingFile(fileURL, startAt: resumeAt, resetSeparation: false)
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
        startStreamPlayback(
            url: remoteURL,
            songID: song.id,
            expectedDuration: expectedDuration,
            startAt: resumeAt,
            resetSeparationOnCacheReady: false
        )
    }

    /// Returns true when a pause request matched an active or resumable playback path.
    @discardableResult
    private func pauseCurrentPlayback(source: String = #function) -> Bool {
        if !handlingAudioSessionInterruption {
            wasPlayingBeforeInterruption = false
        }
        if isRadioMode {
            let wasActive = radioPlaybackRequested || isPlaying || isBuffering
            guard let player = radioPlayer else {
                radioPlaybackRequested = false
                setPlaybackState(
                    playing: false,
                    buffering: false,
                    forceNowPlayingUpdate: true,
                    reason: "pause.radio.noPlayer.\(source)"
                )
                return wasActive
            }
            guard wasActive else {
                setPlaybackState(
                    playing: false,
                    buffering: false,
                    forceNowPlayingUpdate: true,
                    reason: "pause.radio.alreadyPaused.\(source)"
                )
                return true
            }
            radioPlaybackRequested = false
            lastKnownPlaybackTime = activePlaybackTime()
            player.pause()
            setPlaybackState(playing: false, buffering: false, reason: "pause.radio.\(source)")
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
        aiStemSwitchInFlightSongID = nil
        setPlaybackState(playing: false, buffering: false, reason: "pause.file.\(source)")
        return true
    }

    /// Returns true when a resume request could be applied to the current playback path.
    @discardableResult
    private func resumeCurrentPlayback(source: String = #function) -> Bool {
        if isRadioMode {
            guard let player = radioPlayer else {
                radioPlaybackRequested = false
                setPlaybackState(playing: false, buffering: false, reason: "resume.radio.noPlayer.\(source)")
                return false
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
        guard let song = currentSong else { return false }
        // End-of-queue pauses the engine with the deck's scheduled segment
        // fully consumed but currentURL still set; resuming that node would
        // report isPlaying while rendering silence, so reload from the start
        // through the normal start-playing path instead.
        let deckExhausted = avEngine.currentURL != nil && !avEngine.hasScheduledMedia
        if !isPlaying, avEngine.currentURL == nil || deckExhausted {
            let resumeAt = deckExhausted ? 0 : (preferredStreamResumeTime(for: song) ?? lastKnownPlaybackTime)
            if let fileURL = localPlaybackFileURL(for: song) {
                clearPreferredStreamResumeTime()
                startPlayingFile(fileURL, startAt: resumeAt)
                return true
            }
            if let remoteURL = song.audioURL {
                let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
                startStreamPlayback(
                    url: remoteURL,
                    songID: song.id,
                    expectedDuration: expectedDuration,
                    startAt: resumeAt
                )
                return true
            }
            setPlaybackState(
                playing: false,
                buffering: false,
                reason: "resume.file.noSource.\(source)"
            )
            return false
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
        configureAudioSessionCategory()
        activateAudioSession()
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
            cancelPendingTransitionWork()
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
            cancelPendingTransitionWork()
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
        transitionCoordinator.reset()
        #if canImport(UIKit)
            beginTrackTransitionBackgroundTask()
        #endif
        configureAudioSessionCategory()
        activateAudioSession()
        if repeatMode == .one, let current = currentSong {
            // Repeat-one replay: not a new listen, so don't count it again.
            play(song: current, context: [], resetTransitionVolume: true, reportsPlayCount: false)
            return
        }
        if let current = currentSong, !queue.isEmpty,
           let idx = queue.firstIndex(where: { $0.id == current.id }),
           idx + 1 < queue.count
        {
            play(song: queue[idx + 1])
        } else if repeatMode == .all, let first = queue.first {
            play(song: first)
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
        guard let current = currentSong, !queue.isEmpty,
              let idx = queue.firstIndex(where: { $0.id == current.id }),
              idx - 1 >= 0
        else {
            seek(to: 0)
            return
        }
        play(song: queue[idx - 1])
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

    func playInOrder(song: Song, context: [Song]) {
        isShuffled = false
        originalQueue = []
        play(song: song, context: context)
    }

    func playShuffled(from songs: [Song]) {
        guard let pick = songs.randomElement() else { return }
        let shuffled = [pick] + songs.filter { $0.id != pick.id }.shuffled()
        isShuffled = true
        play(song: pick, context: shuffled)
        originalQueue = songs
    }

    func toggleAutoplay() {
        autoplayEnabled.toggle()
    }

    func moveInUpNext(from source: IndexSet, to destination: Int) {
        guard let current = currentSong,
              let baseIdx = queue.firstIndex(where: { $0.id == current.id })
        else { return }
        let upNextStart = baseIdx + 1
        guard upNextStart < queue.count else { return }
        var upNext = Array(queue[upNextStart...])
        upNext.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue[..<upNextStart]) + upNext
    }

    func removeFromUpNext(at offsets: IndexSet) {
        guard let current = currentSong,
              let baseIdx = queue.firstIndex(where: { $0.id == current.id })
        else { return }
        let upNextStart = baseIdx + 1
        guard upNextStart < queue.count else { return }
        var upNext = Array(queue[upNextStart...])
        upNext.remove(atOffsets: offsets)
        queue = Array(queue[..<upNextStart]) + upNext
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
        let alreadyOnSameStation = isRadioMode && currentSong?.id == song.id
        if alreadyOnSameStation {
            currentSong = song
            radioArtworkURL = artworkURL
            updateNowPlayingInfo(reloadArtwork: true)
            return
        }
        cancelPendingTransitionWork()
        avEngine.stop()
        aiStemSwitchInFlightSongID = nil
        stopStreamPlayer()
        instrumentalTask?.cancel()
        instrumentalTask = nil
        preparedStemTask?.cancel()
        preparedStemTask = nil
        preparedStemSongID = nil
        deferredAIEffect = nil
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        scheduleIdleCacheCompression(excluding: Set<String>())
        isRadioMode = true
        radioArtworkURL = artworkURL
        progress = 0
        queue = []
        originalQueue = []
        currentSong = song
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
        autoplay: Bool = true,
        resetSeparationOnCacheReady: Bool = true
    ) {
        stopStreamPlayer()
        stopRadioPlayer()
        avEngine.stop()
        aiStemSwitchInFlightSongID = nil
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
                        startPlayingFile(
                            cachedURL,
                            startAt: resumeAt,
                            resetSeparation: resetSeparationOnCacheReady
                        )
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

        _ = AudioCacheStore.ensureSongDirectory(for: songID)
        let finalURL = AudioCacheStore.mainAudioURL(for: songID, sourceURL: remoteURL)
        let partialURL = AudioCacheStore.mainPartialAudioURL(for: songID, sourceURL: remoteURL)
        DebugLogger.log("Remote playback cache start for \(songID)", category: .cache)
        try? FileManager.default.removeItem(at: partialURL)

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

        try? FileManager.default.removeItem(at: partialURL)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
        } catch {
            try FileManager.default.copyItem(at: temporaryURL, to: partialURL)
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        try Task.checkCancellation()

        guard AudioCacheStore.isPlayableAudioFile(at: partialURL) else {
            try? FileManager.default.removeItem(at: partialURL)
            throw RemotePlaybackCacheError.invalidAudio
        }
        let actualDuration = AudioCacheStore.audioDuration(at: partialURL)
        guard AudioCacheStore.durationAppearsComplete(
            actualDuration: actualDuration,
            expectedDuration: expectedDuration
        ) else {
            try? FileManager.default.removeItem(at: partialURL)
            throw RemotePlaybackCacheError.invalidAudio
        }

        try AudioCacheStore.commitMainAudioFile(
            at: partialURL,
            to: finalURL,
            for: songID
        )
        AudioCacheStore.writeMainSourceURL(remoteURL, for: songID)
        DebugLogger.log("Remote playback cache complete for \(songID)", category: .cache)
        return finalURL
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
        streamFadeGeneration &+= 1
        streamFadeTimer?.cancel()
        streamFadeTimer = nil
        streamPlayer?.pause()
        streamPlayer?.replaceCurrentItem(with: nil)
        streamPlayer = nil
        streamStartedAt = nil
    }

    private func fadeOutStreamPlayer(duration: TimeInterval) {
        guard streamPlayer != nil else { return }
        streamFadeGeneration &+= 1
        let gen = streamFadeGeneration
        streamFadeTimer?.cancel()
        let interval = AVEnginePlayback.transitionTimerInterval
        let steps = max(1, Int((duration / interval).rounded(.up)))
        let counter = TimerStepCounter()
        let timer = DispatchSource.makeTimerSource(queue: Self.volumeRampQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { timer.cancel(); return }
                    guard self.streamFadeGeneration == gen else { return }
                    counter.step += 1
                    let t = Float(counter.step) / Float(max(1, steps))
                    self.streamPlayer?.volume = max(0, 1.0 - t)
                    if t >= 1.0 {
                        // Bump the generation so a tick already enqueued on
                        // main before the cancel can't re-enter and force the
                        // volume back to 0 after the fade completed.
                        self.streamFadeGeneration &+= 1
                        self.streamFadeTimer = nil
                        timer.cancel()
                    }
                }
            }
        }
        streamFadeTimer = timer
        timer.resume()
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
        preparedStemTask?.cancel()
        preparedStemTask = nil
        resetEasterEggWork()
        preparedStemSongID = nil
        deferredAIEffect = nil
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        VocalSeparator.shared.cleanupRealtimeTemp()
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(
            at: AudioPlayerManager.audioCacheDir, includingPropertiesForKeys: nil
        ) {
            for url in entries {
                try? fm.removeItem(at: url)
            }
        }
        #if canImport(UIKit)
            AudioPlayerManager.artworkCache.removeAllObjects()
            nowPlayingArtwork = nil
        #endif
        CacheManager.shared.refreshSizes()
    }

    private func stemsForCachedAIMode(song: Song) -> CachedStems? {
        guard aiEnabled, anyAIEffectActive, !isRadioMode, VocalSeparator.shared.isAvailable else {
            return nil
        }
        return immediatelyCachedStems(for: song, sourceURL: localPlaybackFileURL(for: song))
    }

    private func triggerBackgroundAnalysis(for song: Song) {
        guard aiEnabled, aiAutoAnalyze, !isRadioMode, !anyAIEffectActive else { return }
        guard VocalSeparator.shared.isAvailable else { return }

        if VocalSeparator.shared.hasCachedStems(forSongID: song.id) {
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
            backgroundAnalysisRetryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self,
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
        preparedStemTask?.cancel()
        preparedStemTask = nil
        separationGeneration &+= 1
        let gen = separationGeneration
        guard aiEnabled, !isRadioMode, let song = currentSong else {
            VocalSeparator.shared.cancel()
            preparedStemSongID = nil
            if avEngine.mode == .aiStems { avEngine.revertToMain() }
            if aiEnabled, aiAutoAnalyze, !isRadioMode, let song = currentSong {
                triggerBackgroundAnalysis(for: song)
            }
            return
        }
        guard VocalSeparator.shared.isAvailable else {
            preparedStemSongID = nil
            if avEngine.mode == .aiStems { avEngine.revertToMain() }
            return
        }
        let shouldKeepPreparedStems = keepPreparedStems(for: song)
        guard anyAIEffectActive || shouldKeepPreparedStems else {
            VocalSeparator.shared.cancel()
            if avEngine.mode == .aiStems { avEngine.revertToMain() }
            if aiAutoAnalyze {
                triggerBackgroundAnalysis(for: song)
            }
            return
        }
        if shouldKeepPreparedStems, !anyAIEffectActive {
            if avEngine.mode == .aiStems {
                avEngine.revertToMain()
            }
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
        if let sourceURL = localPlaybackFileURL(for: song) {
            if let stems = immediatelyCachedStems(for: song, sourceURL: sourceURL) {
                DebugLogger.log("Using cached stems for \(song.id)", category: .ai)
                preparedStemSongID = song.id
                switchActivePlaybackToStems(
                    for: song, stems: stems, sourceURL: sourceURL,
                    onReady: { [weak self] in self?.applyAIMixVolumes() }
                )
                return
            }
            // Compressed-only stem caches are decompressed off the main thread
            // before falling back to real-time separation.
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let stems = await cachedStems(for: song, sourceURL: sourceURL) else {
                    guard separationGeneration == gen,
                          currentSong?.id == song.id
                    else { return }
                    startRealTimeSeparation(for: song, generation: gen)
                    return
                }
                guard separationGeneration == gen,
                      currentSong?.id == song.id
                else { return }
                guard avEngine.mode != .aiStems else {
                    applyAIMixVolumes()
                    return
                }
                guard anyAIEffectActive else { return }
                DebugLogger.log("Using cached stems for \(song.id)", category: .ai)
                preparedStemSongID = song.id
                switchActivePlaybackToStems(
                    for: song, stems: stems, sourceURL: sourceURL,
                    onReady: { [weak self] in self?.applyAIMixVolumes() }
                )
            }
            return
        }
        startRealTimeSeparation(for: song, generation: gen)
    }

    private func startRealTimeSeparation(for song: Song, generation gen: UInt64) {
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
                if Task.isCancelled { return }
                guard separationGeneration == gen,
                      self.currentSong?.id == songID, anyAIEffectActive
                else {
                    if stems.isTemporary {
                        VocalSeparator.shared.cleanupRealtimeTemp()
                    }
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
        guard !audioSessionCategoryConfigured else { return }
        do {
            if #available(iOS 13.0, *) {
                try AVAudioSession.sharedInstance().setCategory(
                    .playback, mode: .default, policy: .longFormAudio, options: []
                )
            } else {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            }
            audioSessionCategoryConfigured = true
        } catch {
            DebugLogger.log("Audio session category configuration failed: \(error)", category: .playback)
        }
    }

    private func activateAudioSession() {
        guard !audioSessionIsActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioSessionIsActive = true
        } catch {
            DebugLogger.log("Audio session activation failed: \(error)", category: .playback)
        }
    }

    private func syncSystemVolume(
        _ systemVolume: Float = AVAudioSession.sharedInstance().outputVolume
    ) {
        let reconciledVolume = SystemVolumeReconciliation.value(
            currentVolume: volume,
            systemVolume: systemVolume,
            isUserScrubbing: isUserScrubbingVolume
        )
        if volume != reconciledVolume {
            volume = reconciledVolume
        }
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
        audioSessionCategoryConfigured = false
        audioSessionIsActive = false
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
            audioSessionIsActive = false
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
                let resumed = self.resumeCurrentPlayback(source: "remote.play")
                // In-app play/pause buttons carry their own `.commit`; the
                // remote surfaces had none. iOS suppresses haptics while
                // backgrounded, so in practice this is felt when the app is
                // foreground and the command comes from headphones or
                // Control Center.
                if resumed { AppHaptic.commit.play() }
                return resumed ? .success : .commandFailed
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
                    let resumed = self.resumeCurrentPlayback(source: "remote.pauseAsPlay")
                    if resumed { AppHaptic.commit.play() }
                    return resumed ? .success : .commandFailed
                }
                let paused = self.pauseCurrentPlayback(source: "remote.pause")
                if paused { AppHaptic.commit.play() }
                return paused ? .success : .commandFailed
            }
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return performOnMain {
                DebugLogger.log("Remote toggle command received", category: .playback)
                let toggled = self.togglePlayPause(source: "remote.toggle")
                if toggled { AppHaptic.commit.play() }
                return toggled ? .success : .commandFailed
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
        let diagnosticState =
            "item=\(hasCurrentItem), play=\(cc.playCommand.isEnabled), pause=\(cc.pauseCommand.isEnabled), toggle=\(cc.togglePlayPauseCommand.isEnabled), requested=\(isPlaybackRequested)"
        guard lastRemoteCommandDiagnosticState != diagnosticState else { return }
        lastRemoteCommandDiagnosticState = diagnosticState
        DebugLogger.log(
            "Remote commands availability: \(diagnosticState)",
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

        guard isEasterEggEnabled, !isRadioMode else { return }
        if song.id == easterEggSongID { return }

        if containsChinese(song.title) {
            queueEasterEggSong()
            return
        }

        easterEggLyricsTask = Task { [weak self] in
            guard let self else { return }
            let lyrics = await self.fetchLyricsForEasterEgg(songID: song.id)
            guard !Task.isCancelled, let lyrics else { return }
            let hasChinese = lyrics.contains { self.containsChinese($0.text) }
            if hasChinese, Bool.random() {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.currentSong?.id == song.id else { return }
                    self.queueEasterEggSong()
                }
            }
        }
    }

    private var isEasterEggEnabled: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "nk.easterEggEnabled")
        #else
            false
        #endif
    }

    private func resetEasterEggWork() {
        easterEggQueuedForCurrentSong = false
        easterEggLyricsTask?.cancel()
        easterEggLyricsTask = nil
        easterEggSongTask?.cancel()
        easterEggSongTask = nil
    }

    private func containsChinese(_ text: String) -> Bool {
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
        guard var request = try? KaraokeAPIClient.request(
            pathSegments: ["api", "songs", songID, "lyrics"]
        ) else { return nil }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
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
        guard isEasterEggEnabled else { return }
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
        // Staleness fence (same idea as remotePlaybackCacheToken): the fetch
        // is unstructured, so if the user starts other playback while it is
        // in flight, the completion must not stomp that playback.
        let fenceSongID = currentSong?.id
        let requestToken = UUID()
        fetchRandomTrendingToken = requestToken
        Task {
            guard let songs = try? await KaraokeAPIClient.trendingSongs(days: 7, take: 50),
                  let random = songs.randomElement()
            else {
                // Only touch state/the background task while this request
                // still owns the playback flow.
                guard fetchRandomTrendingToken == requestToken, currentSong?.id == fenceSongID else { return }
                setPlaybackState(
                    playing: false,
                    buffering: false,
                    reason: "fetchRandomTrending.failed"
                )
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
            guard fetchRandomTrendingToken == requestToken, currentSong?.id == fenceSongID else { return }
            play(song: random, context: rotatedQueue)
        }
    }

    private func reportPlayCount(for songID: String) {
        Task {
            guard var req = try? KaraokeAPIClient.request(
                pathSegments: ["api", "songs", "playCount", songID]
            ) else { return }
            req.httpMethod = "PUT"
            // Fire and forget: the result is discarded, so a retry only costs
            // requests. One skipped song used to cost 3 of these.
            let _ = try? await KaraokeAPIClient.data(for: req, allowsRetry: false)
        }
    }

    private func enrichSongMetadataIfNeeded(for song: Song) {
        guard !song.hasArtistMetadata else { return }
        guard enrichmentAttemptedSongIDs.insert(song.id).inserted else { return }
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
                    play(song: plan.nextSong, resetTransitionVolume: true)
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
        preparedStemTask?.cancel()
        preparedStemTask = nil
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        quickCutGeneration &+= 1
        let gen = quickCutGeneration
        let fadeDuration = plan.fadeDuration
        let song = plan.nextSong
        let interval = AVEnginePlayback.transitionTimerInterval
        let steps = max(1, Int((fadeDuration / interval).rounded(.up)))
        let counter = TimerStepCounter()
        let timer = DispatchSource.makeTimerSource(queue: Self.volumeRampQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { timer.cancel(); return }
                    guard self.quickCutGeneration == gen else { return }
                    guard self.transitionCoordinator.state.isCrossfading, !self.isRadioMode else {
                        self.cancelPendingTransitionWork()
                        return
                    }
                    counter.step += 1
                    let t = Float(counter.step) / Float(max(1, steps))
                    self.avEngine.setMasterVolume(1.0 - t)
                    if t >= 1.0 {
                        // Bump the generation so a tick already enqueued on
                        // main before the cancel can't re-enter and tear down
                        // the transition state for the song play() just started.
                        self.quickCutGeneration &+= 1
                        self.quickCutTimer = nil
                        DebugLogger.log("Quick cut transition complete -> play(\(song.id))", category: .playback)
                        self.activeCrossfadePlan = nil
                        self.transitionCoordinator.reset()
                        self.avEngine.setMasterVolume(0)
                        self.play(song: song, resetTransitionVolume: false)
                        self.avEngine.setMasterVolume(1.0)
                        timer.cancel()
                    }
                }
            }
        }
        quickCutTimer = timer
        timer.resume()
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
            play(song: plan.nextSong, resetTransitionVolume: true)
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
        if currentSong?.id != song.id {
            progress = 0
            var excludeIDs = activeSongIDs()
            excludeIDs.insert(song.id)
            scheduleIdleCacheCompression(excluding: excludeIDs)
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
