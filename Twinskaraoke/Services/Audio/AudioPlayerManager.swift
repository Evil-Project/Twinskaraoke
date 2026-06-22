import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI

#if canImport(UIKit)
    import SDWebImage
    import UIKit
#endif

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

private final class AudioDownloadSession: NSObject, URLSessionDataDelegate {
    private let songID: String
    private let partialURL: URL
    private let finalURL: URL
    private let minimumPlayableBytes = 512 * 1024
    private var remoteURL: URL?
    private var fileHandle: FileHandle?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var hasReportedPlayableFallback = false
    private var expectedContentLength: Int64 = NSURLSessionTransferSizeUnknown
    private let stateLock = NSLock()
    private var isCancelled = false
    private var retryCount = 0
    private let maxRetries = 3
    private var retryTimer: Timer?
    var onCompletion: ((URL?) -> Void)?
    var onPlayableFallbackReady: ((URL) -> Void)?

    private var partialFileSize: Int {
        (try? partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    init(songID: String) {
        self.songID = songID
        let songFiles = AudioCacheStore.files(for: songID)
        finalURL = songFiles.main
        partialURL = songFiles.mainPartial
        super.init()
    }

    func start(from remoteURL: URL) {
        self.remoteURL = remoteURL
        try? FileManager.default.removeItem(at: partialURL)
        FileManager.default.createFile(atPath: partialURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: partialURL)
        guard fileHandle != nil else {
            try? FileManager.default.removeItem(at: partialURL)
            AudioCacheStore.writeMainSourceURL(nil, for: songID)
            DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        task = session?.dataTask(with: remoteURL)
        task?.resume()
    }

    func cancel() {
        stateLock.lock()
        isCancelled = true
        task?.cancel()
        session?.invalidateAndCancel()
        fileHandle?.closeFile()
        fileHandle = nil
        retryTimer?.invalidate()
        retryTimer = nil
        stateLock.unlock()
        try? FileManager.default.removeItem(at: partialURL)
        AudioCacheStore.writeMainSourceURL(nil, for: songID)
    }

    private func reportPlayableFallbackIfPossible() {
        guard !hasReportedPlayableFallback else { return }
        guard
            let fileSize = try? partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            fileSize >= minimumPlayableBytes
        else { return }
        guard AVEnginePlayback.hasValidAudioHeader(at: partialURL) else { return }
        hasReportedPlayableFallback = true
        let fallbackURL = partialURL
        DispatchQueue.main.async { [weak self] in
            self?.onPlayableFallbackReady?(fallbackURL)
        }
    }

    func urlSession(
        _: URLSession, dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard AudioCacheStore.acceptsAudioResponse(response) else {
            DebugLogger.log(
                "Audio cache download rejected for \(songID): \(response.mimeType ?? "unknown MIME")",
                category: .cache
            )
            completionHandler(.cancel)
            return
        }
        if let http = response as? HTTPURLResponse {
            expectedContentLength = response.expectedContentLength
            DebugLogger.log(
                "Audio cache download response for \(songID): HTTP \(http.statusCode), expectedBytes=\(response.expectedContentLength)",
                category: .cache
            )
        }
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        stateLock.lock()
        let cancelled = isCancelled
        if !cancelled {
            fileHandle?.write(data)
        }
        stateLock.unlock()
        guard !cancelled else { return }
        reportPlayableFallbackIfPossible()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateLock.lock()
        let cancelled = isCancelled
        fileHandle?.closeFile()
        fileHandle = nil
        stateLock.unlock()
        session.invalidateAndCancel()
        guard !cancelled else { return }
        if let error {
            if shouldRetry(error: error) {
                scheduleRetry()
                return
            }
            DebugLogger.log(
                "Audio cache download failed for \(songID): bytes=\(partialFileSize), error=\(error.localizedDescription), retries=\(retryCount)",
                category: .cache
            )
            try? FileManager.default.removeItem(at: partialURL)
            AudioCacheStore.writeMainSourceURL(nil, for: songID)
            DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
            return
        }
        if let http = task.response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            if shouldRetryHTTPStatus(http.statusCode) {
                scheduleRetry()
                return
            }
            DebugLogger.log(
                "Audio cache download failed for \(songID): HTTP \(http.statusCode), bytes=\(partialFileSize)",
                category: .cache
            )
            try? FileManager.default.removeItem(at: partialURL)
            AudioCacheStore.writeMainSourceURL(nil, for: songID)
            DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
            return
        }
        guard let validRemoteURL = remoteURL else {
            DebugLogger.log(
                "Audio cache download failed for \(songID): missing remote URL, bytes=\(partialFileSize)",
                category: .cache
            )
            try? FileManager.default.removeItem(at: partialURL)
            AudioCacheStore.writeMainSourceURL(nil, for: songID)
            DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
            return
        }
        guard AudioCacheStore.isPlayableAudioFile(at: partialURL) else {
            DebugLogger.log(
                "Audio cache download produced unplayable file for \(songID): bytes=\(partialFileSize)",
                category: .cache
            )
            try? FileManager.default.removeItem(at: partialURL)
            AudioCacheStore.writeMainSourceURL(nil, for: songID)
            DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
            return
        }
        try? FileManager.default.removeItem(at: finalURL)
        let completedBytes = partialFileSize
        if expectedContentLength > 0, Int64(completedBytes) < expectedContentLength {
            DebugLogger.log(
                "Audio cache download incomplete for \(songID): bytes=\(completedBytes), expectedBytes=\(expectedContentLength)",
                category: .cache
            )
            try? FileManager.default.removeItem(at: partialURL)
            AudioCacheStore.writeMainSourceURL(nil, for: songID)
            DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
            return
        }
        do {
            try FileManager.default.moveItem(at: partialURL, to: finalURL)
            AudioCacheStore.writeMainSourceURL(validRemoteURL, for: songID)
            DebugLogger.log(
                "Audio cache download completed for \(songID): bytes=\(completedBytes)",
                category: .cache
            )
            let final = finalURL
            DispatchQueue.main.async { [weak self] in self?.onCompletion?(final) }
        } catch {
            DebugLogger.log(
                "Audio cache download move failed for \(songID): \(error.localizedDescription)",
                category: .cache
            )
            try? FileManager.default.removeItem(at: partialURL)
            AudioCacheStore.writeMainSourceURL(nil, for: songID)
            DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
        }
    }

    private func shouldRetry(error: Error) -> Bool {
        guard retryCount < maxRetries else { return false }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func shouldRetryHTTPStatus(_ statusCode: Int) -> Bool {
        guard retryCount < maxRetries else { return false }
        switch statusCode {
        case 408, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    private func scheduleRetry() {
        retryCount += 1
        let delay = min(pow(2.0, Double(retryCount)), 8.0)
        DebugLogger.log(
            "Scheduling retry \(retryCount)/\(maxRetries) for \(songID) after \(delay)s",
            category: .cache
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                guard !isCancelled, let remoteURL else { return }
                DebugLogger.log(
                    "Retrying download for \(songID) (attempt \(retryCount))",
                    category: .cache
                )
                retryTimer = nil
                hasReportedPlayableFallback = false
                expectedContentLength = NSURLSessionTransferSizeUnknown
                try? FileManager.default.removeItem(at: partialURL)
                FileManager.default.createFile(atPath: partialURL.path, contents: nil)
                fileHandle = try? FileHandle(forWritingTo: partialURL)
                guard fileHandle != nil else {
                    try? FileManager.default.removeItem(at: partialURL)
                    AudioCacheStore.writeMainSourceURL(nil, for: songID)
                    onCompletion?(nil)
                    return
                }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.urlCache = nil
                configuration.waitsForConnectivity = false
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 300
                session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                task = session?.dataTask(with: remoteURL)
                task?.resume()
            }
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
                VocalSeparator.shared.cleanupRealtimeTemp()
                if avEngine.mode == .aiStems { avEngine.revertToMain() }
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
                if !anyAIEffectActive, avEngine.mode == .aiStems {
                    avEngine.revertToMain()
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
    private var lastKnownPlaybackTime: TimeInterval = 0
    private var pollTimer: Timer?
    private var streamFadeTimer: Timer?
    private var streamStartedAt: Date?

    private var _suppressModeSwitch = false
    private var originalQueue: [Song] = []
    private var cancellables = Set<AnyCancellable>()
    private var artworkURL: URL?
    private var artworkTask: (any SDWebImageOperation)?
    private var downloadSession: AudioDownloadSession?
    private var currentPlaybackURL: URL?
    private var instrumentalTask: Task<Void, Never>?
    private var backgroundAnalysisRetryTask: Task<Void, Never>?
    private var cacheCompressionTask: Task<Void, Never>?
    private var aiStemSwitchInFlightSongID: String?
    private var quickCutTimer: Timer?
    private var quickCutGeneration: UInt64 = 0
    private var separationGeneration: UInt64 = 0
    private var transitionTimeoutGeneration: UInt64 = 0
    private var activeCrossfadePlan: TransitionCoordinator.TransitionPlan?
    private var suppressPlaybackEndedUntil: Date = .distantPast
    private var wasPlayingBeforeInterruption = false

    #if canImport(UIKit)
        private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        private var trackTransitionTaskID: UIBackgroundTaskIdentifier = .invalid
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

    var anyAIEffectActive: Bool {
        karaokeMode || bassEnhanceMode || vocalEnhanceMode || instrumentalEnhanceMode
    }

    private var shouldDeferAIEffectActivation: Bool {
        guard aiEnabled, aiAutoAnalyze, !isRadioMode else { return false }
        guard currentSong != nil else { return false }
        return !isKaraokePreparedForCurrentSong
    }

    private var isPlaybackRequested: Bool {
        if isRadioMode { return radioPlaybackRequested }
        if isStreamMode { return streamPlaybackRequested }
        return isPlaying
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
        reloadArtwork: Bool = false
    ) {
        let changed = isPlaying != playing || isBuffering != buffering || reloadArtwork
        isPlaying = playing
        isBuffering = buffering
        if changed {
            updateNowPlayingInfo(reloadArtwork: reloadArtwork)
        }
    }

    init() {
        configureAudioSessionCategory()
        activateAudioSession()
        AudioPlayerManager.cleanupOrphanPartialCacheFiles()
        DebugLogger.log("AudioPlayerManager initializing", category: .playback)
        #if os(iOS)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        #endif
        setupRemoteCommands()

        avEngine.onPlaybackEnded = { [weak self] in
            guard let self, !self.isRadioMode else { return }
            guard isPlaying else { return }
            guard !avEngine.isCrossfading else { return }
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
            isPlaying = false
            isBuffering = false
            updateNowPlayingInfo(reloadArtwork: false)
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
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in self?.handleBackgroundTransition() }
                .store(in: &cancellables)
            NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
                .sink { [weak self] _ in self?.handleMemoryWarning() }
                .store(in: &cancellables)
        #endif
    }

    deinit {
        pollTimer?.invalidate()
        quickCutTimer?.invalidate()
        streamFadeTimer?.invalidate()
        instrumentalTask?.cancel()
        backgroundAnalysisRetryTask?.cancel()
        if let existing = radioTimeObserver {
            existing.player.removeTimeObserver(existing.token)
        }
        artworkTask?.cancel()
        downloadSession?.cancel()
        cacheCompressionTask?.cancel()
        radioPlayer?.pause()
        #if canImport(UIKit)
            let backgroundTaskID = bgTaskID
            let transitionTaskID = trackTransitionTaskID
            bgTaskID = .invalid
            trackTransitionTaskID = .invalid
            if backgroundTaskID != .invalid || transitionTaskID != .invalid {
                Task { @MainActor in
                    if backgroundTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    }
                    if transitionTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(transitionTaskID)
                    }
                }
            }
        #endif
    }

    private func cancelBackgroundAnalysisRetry() {
        backgroundAnalysisRetryTask?.cancel()
        backgroundAnalysisRetryTask = nil
    }

    private func cancelDownloadSession() {
        downloadSession?.cancel()
        downloadSession = nil
        #if canImport(UIKit)
            endAudioCacheBackgroundTask()
        #endif
    }

    private func completeDownloadSession(_ session: AudioDownloadSession?) -> Bool {
        guard let session, downloadSession === session else { return false }
        downloadSession = nil
        #if canImport(UIKit)
            endAudioCacheBackgroundTask()
        #endif
        return true
    }

    private func localPlaybackFileURL(for song: Song) -> URL? {
        if let downloaded = DownloadManager.shared.playableURL(for: song) {
            return downloaded
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        return AudioCacheStore.playableMainURL(for: song.id, expectedRemoteURL: song.audioURL, expectedDuration: expectedDuration)
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
            DebugLogger.log(
                "Removing suspect downloaded audio after premature end for \(song.id)",
                category: .cache
            )
            DownloadManager.shared.remove(songID: song.id)
            currentPlaybackURL = nil
        }

        if let remoteURL = song.audioURL {
            avEngine.stop()
            startStreamPlayback(
                url: remoteURL,
                songID: song.id,
                startAt: max(0, elapsed),
                autoplay: isPlaybackRequested
            )
        } else {
            setPlaybackState(playing: false, buffering: false)
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
        guard !isRadioMode else { return }
        suppressPlaybackEndedCallbacks()
        let shouldResume = isPlaybackRequested
        let startAt = activePlaybackTime(for: song)
        currentPlaybackURL = sourceURL
        aiStemSwitchInFlightSongID = song.id
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
        isPlaying = shouldResume
        isBuffering = false
        updateNowPlayingInfo(reloadArtwork: false)
    }

    private func cancelQuickCutTimer(resetVolume: Bool = true) {
        quickCutTimer?.invalidate()
        quickCutTimer = nil
        if resetVolume {
            avEngine.setMasterVolume(1.0)
        }
    }

    private func cancelPendingTransitionWork(resetVolume: Bool = true) {
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
        cancelDownloadSession()
        instrumentalTask?.cancel()
        instrumentalTask = nil
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

    private func play(song: Song, context: [Song] = [], resetTransitionVolume: Bool) {
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
        if currentSong?.id != song.id {
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
        cancelDownloadSession()
        let fileURL = localPlaybackFileURL(for: song)
        if let fileURL, let stems = stemsForCachedAIMode(song: song) {
            instrumentalTask?.cancel()
            instrumentalTask = nil
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
            isPlaying = true
            isBuffering = false
            updateNowPlayingInfo(reloadArtwork: true)
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
        startStreamPlayback(url: remoteURL, songID: song.id)
        if aiEnabled {
            if anyAIEffectActive {
                applyMLSeparationIfNeeded()
            } else if aiAutoAnalyze {
                triggerBackgroundAnalysis(for: song)
            }
        }
        let songID = song.id
        let session = AudioDownloadSession(songID: songID)
        downloadSession = session
        session.onPlayableFallbackReady = { [weak self, weak session] fallbackURL in
            guard let self else { return }
            guard downloadSession === session else { return }
            guard let currentSong, currentSong.id == songID else { return }
            switchSilentStreamToLocalFallback(fallbackURL, for: currentSong)
        }
        session.onCompletion = { [weak self, weak session] url in
            guard let self else { return }
            guard completeDownloadSession(session) else { return }
            guard let url else { return }
            CacheManager.shared.recordAccess(for: url)
            let protectedIDs = activeSongIDs()
            CacheManager.shared.enforceMusicCacheLimits(excluding: protectedIDs)
            guard let currentSong, currentSong.id == songID else { return }
            let expectedDuration = currentSong.duration > 0 ? TimeInterval(currentSong.duration) : nil
            guard
                let playableURL = AudioCacheStore.playableMainURL(
                    for: songID,
                    expectedRemoteURL: currentSong.audioURL,
                    expectedDuration: expectedDuration
                )
            else { return }
            if isStreamMode, currentPlaybackURL?.path != playableURL.path {
                let resumeAt = max(0, activePlaybackTime(for: currentSong))
                let shouldAutoplay = streamPlaybackRequested || isPlaying
                startStreamPlayback(
                    url: playableURL,
                    songID: songID,
                    startAt: resumeAt,
                    autoplay: shouldAutoplay
                )
            }
            currentPlaybackURL = playableURL
            prepareBackgroundStemPlaybackIfPossible(for: currentSong)
            if anyAIEffectActive {
                applyMLSeparationIfNeeded()
            } else if aiEnabled, aiAutoAnalyze {
                triggerBackgroundAnalysis(for: currentSong)
            }
        }
        session.start(from: remoteURL)
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
    }

    private func startPlayingFile(_ url: URL, startAt: TimeInterval = 0) {
        suppressPlaybackEndedCallbacks()
        stopRadioPlayer()
        stopStreamPlayer()
        instrumentalTask?.cancel()
        instrumentalTask = nil
        separationGeneration &+= 1
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cleanupRealtimeTemp()
        streamStartedAt = nil
        currentPlaybackURL = url
        configureAudioSessionCategory()
        activateAudioSession()
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        avEngine.play(url: url, startAt: max(0, startAt)) { [weak self] in
            #if canImport(UIKit)
                self?.endTrackTransitionBackgroundTask()
            #endif
        }
        isPlaying = true
        isBuffering = false
        updateNowPlayingInfo(reloadArtwork: true)
        DebugLogger.log("Playing file: \(url.lastPathComponent)", category: .playback)
        CacheManager.shared.recordAccess(for: url)
        if let song = currentSong, aiEnabled, aiAutoAnalyze, !anyAIEffectActive {
            triggerBackgroundAnalysis(for: song)
            prepareBackgroundStemPlaybackIfPossible(for: song)
        }
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
            isPlaying = false
            isBuffering = false
            updateNowPlayingInfo(reloadArtwork: false)
            return
        }
        startStreamPlayback(url: remoteURL, songID: song.id, startAt: resumeAt)
    }

    @discardableResult
    private func pauseCurrentPlayback() -> Bool {
        if isRadioMode {
            guard let player = radioPlayer else {
                radioPlaybackRequested = false
                setPlaybackState(playing: false, buffering: false)
                return false
            }
            radioPlaybackRequested = false
            player.pause()
            setPlaybackState(playing: false, buffering: false)
            return true
        }
        if isStreamMode {
            guard let player = streamPlayer else {
                streamPlaybackRequested = false
                setPlaybackState(playing: false, buffering: false)
                return false
            }
            cancelPendingTransitionWork()
            streamPlaybackRequested = false
            player.pause()
            setPlaybackState(playing: false, buffering: false)
            return true
        }
        guard isPlaying else { return false }
        cancelPendingTransitionWork()
        avEngine.pause()
        setPlaybackState(playing: false, buffering: false)
        return true
    }

    @discardableResult
    private func resumeCurrentPlayback() -> Bool {
        if isRadioMode {
            guard let player = radioPlayer else {
                radioPlaybackRequested = false
                setPlaybackState(playing: false, buffering: false)
                return false
            }
            configureAudioSessionCategory()
            activateAudioSession()
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
            radioPlaybackRequested = true
            setPlaybackState(playing: false, buffering: true)
            player.play()
            refreshManagedPlayerState(player, kind: .radio)
            return true
        }
        if isStreamMode {
            guard let player = streamPlayer else {
                streamPlaybackRequested = false
                setPlaybackState(playing: false, buffering: false)
                return false
            }
            configureAudioSessionCategory()
            activateAudioSession()
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
            streamPlaybackRequested = true
            setPlaybackState(playing: false, buffering: true)
            player.play()
            refreshManagedPlayerState(player, kind: .stream)
            return true
        }
        guard currentSong != nil else { return false }
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        avEngine.resume()
        setPlaybackState(playing: true, buffering: false)
        return true
    }

    @discardableResult
    func togglePlayPause() -> Bool {
        if isPlaybackRequested {
            return pauseCurrentPlayback()
        }
        return resumeCurrentPlayback()
    }

    func pauseIfPlaying() {
        guard isPlaybackRequested else { return }
        pauseCurrentPlayback()
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
            play(song: current)
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
            isPlaying = false
            avEngine.pause()
            updateNowPlayingInfo(reloadArtwork: false)
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
            setPlaybackState(playing: false, buffering: false)
            return
        }
        if item.status == .failed {
            handleManagedPlayerFailure(player: player, item: item, kind: kind)
            return
        }
        let playbackRequested = playbackRequested(for: kind)
        guard playbackRequested else {
            setPlaybackState(playing: false, buffering: false)
            return
        }
        if player.timeControlStatus == .playing {
            setPlaybackState(playing: true, buffering: false)
        } else {
            setPlaybackState(playing: false, buffering: true)
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
        setPlaybackState(playing: false, buffering: false)
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
        let alreadyOnSameStation = isRadioMode && currentSong?.id == song.id
        if alreadyOnSameStation {
            currentSong = song
            radioArtworkURL = artworkURL
            updateNowPlayingInfo(reloadArtwork: true)
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
        cancelDownloadSession()
        scheduleIdleCacheCompression(excluding: Set<String>())
        isRadioMode = true
        radioArtworkURL = artworkURL
        progress = 0
        queue = []
        originalQueue = []
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
        setPlaybackState(playing: false, buffering: true)
        observeManagedPlayer(player, item: item, kind: .radio)
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        player.play()
        updateNowPlayingInfo(reloadArtwork: true)
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
        startAt: TimeInterval = 0,
        autoplay: Bool = true
    ) {
        stopStreamPlayer()
        stopRadioPlayer()
        avEngine.stop()
        currentPlaybackURL = url
        DebugLogger.log(
            "Starting stream playback for \(songID): source=\(playbackSourceDescription(url)), startAt=\(startAt), autoplay=\(autoplay)",
            category: .playback
        )
        configureAudioSessionCategory()
        activateAudioSession()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        if #available(iOS 15.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = 1.0
        streamPlayer = player
        streamStartedAt = Date()
        streamPlaybackRequested = autoplay
        setPlaybackState(playing: false, buffering: autoplay)
        observeManagedPlayer(player, item: item, kind: .stream)
        if startAt > 0 {
            setPreferredStreamResumeTime(startAt, for: songID)
        } else {
            clearPreferredStreamResumeTime()
        }
        streamEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isStreamMode, !self.isRadioMode else { return }
                guard isPlaying else { return }
                guard !avEngine.isCrossfading else { return }
                guard quickCutTimer == nil else { return }
                guard !suppressTransitionAfterSeek else { return }
                guard !isPlaybackEndedCallbackSuppressed else { return }
                if handlePrematurePlaybackEndIfNeeded(source: "Stream AVPlayer") { return }
                playNextOrRandom()
            }
        }
        if autoplay {
            NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        }
        if startAt > 0 {
            let target = CMTime(seconds: startAt, preferredTimescale: 600)
            player.pause()
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) {
                [weak self, weak player] _ in
                Task { @MainActor [weak self, weak player] in
                    guard let self, let player, streamPlayer === player else { return }
                    guard streamPlaybackRequested else {
                        refreshManagedPlayerState(player, kind: .stream)
                        return
                    }
                    player.play()
                    refreshManagedPlayerState(player, kind: .stream)
                }
            }
        } else if autoplay {
            player.play()
        }
        updateNowPlayingInfo(reloadArtwork: true)
    }

    private func switchSilentStreamToLocalFallback(_ fallbackURL: URL, for song: Song) {
        guard isStreamMode, !isRadioMode else { return }
        guard streamPlaybackRequested else { return }
        guard currentSong?.id == song.id else { return }
        guard let startedAt = streamStartedAt, Date().timeIntervalSince(startedAt) >= 3 else { return }
        let streamTime = streamPlayer?.currentTime().seconds ?? .nan
        let hasRemoteProgress = streamTime.isFinite && streamTime > 0.25

        guard !hasRemoteProgress else { return }
        DebugLogger.log(
            "Switching startup-stalled stream to local fallback for \(song.id)",
            category: .playback
        )
        let resumeAt = max(0, activePlaybackTime(for: song))
        startStreamPlayback(url: fallbackURL, songID: song.id, startAt: resumeAt)
    }

    private func stopStreamPlayer() {
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
        guard let player = streamPlayer else { return }
        streamFadeTimer?.invalidate()
        let interval = AVEnginePlayback.transitionTimerInterval
        let steps = max(1, Int((duration / interval).rounded(.up)))
        var step = 0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                step += 1
                let t = Float(step) / Float(max(1, steps))
                player.volume = max(0, 1.0 - t)
                if t >= 1.0 {
                    timer.invalidate()
                    self?.streamFadeTimer = nil
                }
            }
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

    func displayImageURL(for song: Song) -> URL? {
        if isRadioMode, currentSong?.id == song.id, let art = radioArtworkURL {
            return art
        }
        return song.imageURL
    }

    func clearCache() {
        DebugLogger.log("Clearing all cache", category: .cache)
        cancelPendingTransitionWork()
        cacheCompressionTask?.cancel()
        cancelDownloadSession()
        instrumentalTask?.cancel()
        instrumentalTask = nil
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

    private static func cleanupOrphanPartialCacheFiles() {
        AudioCacheStore.cleanupLegacyArtifacts()
    }

    private func stemsForCachedAIMode(song: Song) -> CachedStems? {
        guard aiEnabled, anyAIEffectActive, !isRadioMode, VocalSeparator.shared.isAvailable else {
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
            if wasPlayingBeforeInterruption {
                pauseCurrentPlayback()
            }
        case .ended:
            guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
            if opts.contains(.shouldResume), wasPlayingBeforeInterruption {
                resumeCurrentPlayback()
            }
            wasPlayingBeforeInterruption = false
        @unknown default: break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        updateRouteIcon()
        guard let info = note.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }
        if reason == .oldDeviceUnavailable, isPlaybackRequested {
            pauseCurrentPlayback()
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
            guard let self else { return .commandFailed }
            return resumeCurrentPlayback() ? .success : .commandFailed
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return pauseCurrentPlayback() ? .success : .commandFailed
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return togglePlayPause() ? .success : .commandFailed
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
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            let dur = playbackDuration
            guard dur.isFinite, dur > 0 else { return .commandFailed }
            seek(to: positionEvent.positionTime / dur)
            return .success
        }
    }

    private func updateNowPlayingInfo(reloadArtwork: Bool) {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            lastNowPlayingElapsedSecond = nil
            lastNowPlayingPlaybackRate = nil
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
            info[MPMediaItemPropertyPlaybackDuration] = playbackDuration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackTime
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
        lastNowPlayingElapsedSecond = isRadioMode ? nil : Int(playbackTime.rounded(.down))
        lastNowPlayingPlaybackRate = isPlaying ? 1.0 : 0.0
    }

    private func updateNowPlayingElapsed(_ elapsed: Double) {
        let roundedSecond = Int(elapsed.rounded(.down))
        let playbackRate = isPlaying ? 1.0 : 0.0
        guard roundedSecond != lastNowPlayingElapsedSecond
            || playbackRate != lastNowPlayingPlaybackRate else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        lastNowPlayingElapsedSecond = roundedSecond
        lastNowPlayingPlaybackRate = playbackRate
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
            let pixelSize = NSValue(
                cgSize: CGSize(
                    width: AudioPlayerManager.artworkMaxPixel,
                    height: AudioPlayerManager.artworkMaxPixel
                )
            )
            artworkTask = SDWebImageManager.shared.loadImage(
                with: url,
                options: [.retryFailed, .scaleDownLargeImages],
                context: [.imageThumbnailPixelSize: pixelSize],
                progress: nil
            ) { [weak self] image, _, _, _, _, _ in
                guard let self, currentSong?.id == songID else { return }
                guard let image else { return }
                let squareImage = image.croppedToSquare().downscaled(
                    maxPixel: AudioPlayerManager.artworkMaxPixel
                )
                let cost = Int(
                    squareImage.size.width * squareImage.size.height * squareImage.scale
                        * squareImage.scale * 4
                )
                AudioPlayerManager.artworkCache.setObject(squareImage, forKey: url as NSURL, cost: cost)
                applyArtwork(squareImage, for: songID)
            }
        #endif
    }

    #if canImport(UIKit)
        private func applyArtwork(_ image: UIImage, for songID: String?) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async { [weak self] in
                guard let self, currentSong?.id == songID else { return }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                nowPlayingArtwork = image
            }
        }
    #endif

    #if canImport(UIKit)
        private func handleBackgroundTransition() {
            endAudioCacheBackgroundTask()

            guard downloadSession != nil else { return }
            bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "AudioCache") { [weak self] in
                self?.endAudioCacheBackgroundTask()
            }
        }

        private func endAudioCacheBackgroundTask() {
            guard bgTaskID != .invalid else { return }
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }

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

    private func fetchRandomTrending() {
        guard let url = URL(string: "\(StorageHost.api)/api/explore/trendings?days=7&take=50")
        else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, let songs = try? JSONDecoder().decode([Song].self, from: data),
               let random = songs.randomElement()
            {
                let rotatedQueue: [Song] = if let index = songs.firstIndex(of: random) {
                    Array(songs[index...]) + Array(songs[..<index])
                } else {
                    songs
                }
                DispatchQueue.main.async { [weak self] in
                    self?.play(song: random, context: rotatedQueue)
                }
            } else {
                DispatchQueue.main.async {
                    #if canImport(UIKit)
                        self.endTrackTransitionBackgroundTask()
                    #endif
                }
            }
        }.resume()
    }

    private func reportPlayCount(for songID: String) {
        guard let url = URL(string: "\(StorageHost.api)/api/songs/playCount/\(songID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private func enrichSongMetadataIfNeeded(for song: Song) {
        guard !song.hasArtistMetadata else { return }
        let songID = song.id
        guard let url = URL(string: "\(StorageHost.api)/api/explore/trendings?days=all") else { return }
        let searchURL = URLComponents(string: "\(StorageHost.api)/api/songs")
        var request: URLRequest
        if let searchURL, let u = searchURL.url {
            request = URLRequest(url: u)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            GuestIdentity.applyIfNeeded(to: &request)
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "page": 1, "pageSize": 1, "search": song.title,
            ])
        } else {
            request = URLRequest(url: url)
            GuestIdentity.applyIfNeeded(to: &request)
        }
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data else { return }
            if let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
               let match = response.items.first(where: { $0.id == songID })
            {
                DispatchQueue.main.async {
                    guard let self, self.currentSong?.id == songID else { return }
                    self.currentSong = match
                    self.updateNowPlayingInfo(reloadArtwork: false)
                }
                return
            }
            if let songs = try? JSONDecoder().decode([Song].self, from: data),
               let match = songs.first(where: { $0.id == songID })
            {
                DispatchQueue.main.async {
                    guard let self, self.currentSong?.id == songID else { return }
                    self.currentSong = match
                    self.updateNowPlayingInfo(reloadArtwork: false)
                }
            }
        }.resume()
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
        VocalSeparator.shared.cancel()
        VocalSeparator.shared.cancelBackgroundAnalysis()
        quickCutGeneration &+= 1
        let gen = quickCutGeneration
        let fadeDuration = plan.fadeDuration
        let song = plan.nextSong
        let interval = AVEnginePlayback.transitionTimerInterval
        let steps = max(1, Int((fadeDuration / interval).rounded(.up)))
        var step = 0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.quickCutGeneration == gen else { return }
                guard self.transitionCoordinator.state.isCrossfading, !self.isRadioMode else {
                    self.cancelPendingTransitionWork()
                    return
                }
                step += 1
                let t = Float(step) / Float(max(1, steps))
                self.avEngine.setMasterVolume(1.0 - t)
                if t >= 1.0 {
                    timer.invalidate()
                    self.quickCutTimer = nil
                    DebugLogger.log("Quick cut transition complete -> play(\(song.id))", category: .playback)
                    self.activeCrossfadePlan = nil
                    self.transitionCoordinator.reset()
                    self.avEngine.setMasterVolume(0)
                    self.play(song: song, resetTransitionVolume: false)
                    self.avEngine.setMasterVolume(1.0)
                }
            }
        }
        quickCutTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
        cancelDownloadSession()
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
            withAnimation(.easeInOut(duration: 0.32)) {
                currentSong = song
            }
        }
        upcomingSong = nil
        isPlaying = true
        isBuffering = false
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
