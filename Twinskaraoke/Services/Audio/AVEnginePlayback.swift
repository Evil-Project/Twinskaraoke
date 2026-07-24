import AVFoundation
import Foundation

enum AVEnginePlaybackMode { case single, aiStems }

/// Moves freshly loaded, uniquely referenced audio media out of a background
/// loading task; AVAudioFile is not Sendable but the loader
/// hands over its only reference.
private nonisolated struct LoadedMediaTransfer<Value>: @unchecked Sendable {
    let value: Value
}

enum AVEnginePlaybackRampStyle {
    case equalPower
    case linear
}

extension AVAudioTime {
    static func now() -> AVAudioTime {
        AVAudioTime(hostTime: mach_absolute_time())
    }

    func offset(seconds: TimeInterval) -> AVAudioTime {
        let hostTimeOffset = AVAudioTime.hostTime(forSeconds: seconds)
        return AVAudioTime(hostTime: hostTime + hostTimeOffset)
    }
}

@MainActor
final class SimpleAudioPlayer {
    let playerNode = AVAudioPlayerNode()
    let sourceMixer = AVAudioMixerNode()
    var completionHandler: (() -> Void)?

    private var loadedFile: AVAudioFile?
    private var seekOffset: TimeInterval = 0
    private var pausedPosition: TimeInterval?
    private var _isPaused = false
    private var scheduleGeneration: UInt64 = 0

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    var duration: TimeInterval {
        if let file = loadedFile {
            guard file.fileFormat.sampleRate > 0 else { return 0 }
            return Double(file.length) / file.fileFormat.sampleRate
        }
        return 0
    }

    var currentTime: TimeInterval {
        guard playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return pausedPosition ?? seekOffset }
        return seekOffset + max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
    }

    func load(file: AVAudioFile) throws {
        invalidateScheduledPlayback()
        loadedFile = file
        seekOffset = 0
        pausedPosition = nil
        _isPaused = false
    }

    func unload() {
        invalidateScheduledPlayback()
        loadedFile = nil
        seekOffset = 0
        pausedPosition = nil
        _isPaused = false
    }

    func play() {
        if _isPaused {
            _isPaused = false
            pausedPosition = nil
            playerNode.play()
            return
        }
        play(from: 0)
    }

    func play(from seconds: TimeInterval, at time: AVAudioTime? = nil) {
        _isPaused = false
        invalidateScheduledPlayback()
        seekOffset = max(0, seconds)
        pausedPosition = nil

        let generation = scheduleGeneration
        guard let file = loadedFile, scheduleFileSegment(file, at: time) else {
            // Preserve the asynchronous shape of a natural node completion.
            // A later stop/load invalidates this generation before delivery.
            Task { @MainActor [weak self] in
                self?.deliverCompletion(for: generation)
            }
            return
        }

        if let time {
            playerNode.play(at: time)
        } else {
            playerNode.play()
        }
    }

    func pause() {
        pausedPosition = currentTime
        playerNode.pause()
        _isPaused = true
    }

    func stop() {
        invalidateScheduledPlayback()
        _isPaused = false
        seekOffset = 0
        pausedPosition = nil
    }

    private func invalidateScheduledPlayback() {
        scheduleGeneration &+= 1
        // Completion handlers can run when stop() unschedules media. Incrementing
        // first makes those callbacks stale by construction.
        playerNode.stop()
    }

    @discardableResult
    private func scheduleFileSegment(_ file: AVAudioFile, at time: AVAudioTime?) -> Bool {
        let sampleRate = file.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekOffset * sampleRate)
        let remaining = AVAudioFrameCount(max(0, file.length - startFrame))
        guard remaining > 0 else { return false }
        let generation = scheduleGeneration
        playerNode.scheduleSegment(
            file, startingFrame: startFrame, frameCount: remaining, at: time,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.deliverCompletion(for: generation)
            }
        }
        return true
    }

    private func deliverCompletion(for generation: UInt64) {
        guard scheduleGeneration == generation else { return }
        completionHandler?()
    }

    #if DEBUG
        var scheduleGenerationForTesting: UInt64 { scheduleGeneration }
        var loadedFileFormatForTesting: AVAudioFormat? { loadedFile?.processingFormat }

        func deliverCompletionForTesting(scheduledGeneration: UInt64) {
            deliverCompletion(for: scheduledGeneration)
        }
    #endif
}

@MainActor
final class AVEnginePlayback {
    typealias Mode = AVEnginePlaybackMode
    typealias RampStyle = AVEnginePlaybackRampStyle
    private typealias LoadedMedia = AVAudioFile
    private typealias LoadedStemPair = (LoadedMedia, LoadedMedia)
    private typealias LoadedStemTriple = (LoadedMedia, LoadedMedia, LoadedMedia)
    private enum MediaLoadIntent {
        case immediatePlayback
        case prefetch
    }

    private let engine = AVAudioEngine()
    private var mainPlayer = SimpleAudioPlayer()
    private var crossfadePlayer = SimpleAudioPlayer()
    let stemVocals = SimpleAudioPlayer()
    let stemInstrumental = SimpleAudioPlayer()
    let instEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let mainMixer = AVAudioMixerNode()
    let userEQ = AVAudioUnitEQ(numberOfBands: 10)

    private(set) var mode: Mode = .single
    private(set) var currentURL: URL?
    private(set) var aiStartOffset: TimeInterval = 0

    // Read from audio-thread completion callbacks to detect stale completions;
    // written only on the main actor.
    private nonisolated(unsafe) var suppressionToken: UInt64 = 0
    private var _paused: Bool = false

    private(set) var isCrossfading = false

    private var crossfadeTimer: DispatchSourceTimer?
    private var crossfadeRampGeneration: UInt64 = 0
    private var singleLoadTask: Task<LoadedMediaTransfer<LoadedMedia>, Error>?
    private var stemsLoadTask: Task<LoadedMediaTransfer<LoadedStemTriple>, Error>?
    private var switchToStemsLoadTask: Task<LoadedMediaTransfer<LoadedStemPair>, Error>?
    private var crossfadePreloadTask: Task<LoadedMediaTransfer<LoadedMedia>, Error>?
    private var primaryLoadGeneration: UInt64 = 0
    private var crossfadeLoadGeneration: UInt64 = 0
    private var preparedCrossfadeMedia: LoadedMedia?

    var onCrossfadeCompleted: (() -> Void)?
    var onCrossfadeStarted: (() -> Void)?

    var onPlaybackEnded: (() -> Void)?
    var onPlaybackError: ((Error) -> Void)?
    var onEngineConfigurationChange: (() -> Void)?

    var isEngineRunning: Bool {
        engine.isRunning
    }

    static let eqBandCount = 10
    static let bandFrequencies: [Float] = [
        31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
    ]
    private var engineConfigObserver: Any?

    private nonisolated static let constrainedMemoryThreshold: UInt64 = 4 * 1024 * 1024 * 1024
    private nonisolated static let constrainedTransitionTicksPerSecond: Double = 18
    private nonisolated static let defaultTransitionTicksPerSecond: Double = 24
    private nonisolated static let crossfadeRampQueue = DispatchQueue(
        label: "com.Mag1cByt3s.Twinskaraoke.crossfade-ramp",
        qos: .userInteractive
    )

    init() {
        let outputSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sessionSampleRate = AVAudioSession.sharedInstance().sampleRate
        let graphSampleRate: Double
        if outputSampleRate.isFinite, outputSampleRate > 0 {
            graphSampleRate = outputSampleRate
        } else if sessionSampleRate.isFinite, sessionSampleRate > 0 {
            graphSampleRate = sessionSampleRate
        } else {
            graphSampleRate = 48_000
        }
        let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: graphSampleRate,
            channels: 2, interleaved: false
        )!
        DebugLogger.log(
            "Audio graph configured at \(Int(graphSampleRate)) Hz; source decks use each file's native processing format",
            category: .playback
        )

        let players = [mainPlayer, crossfadePlayer, stemVocals, stemInstrumental]
        for player in players {
            engine.attach(player.playerNode)
            engine.attach(player.sourceMixer)
            engine.connect(player.playerNode, to: player.sourceMixer, format: fmt)
        }
        engine.attach(instEQ)
        engine.attach(mainMixer)
        engine.attach(userEQ)

        engine.connect(mainPlayer.sourceMixer, to: mainMixer, format: fmt)
        engine.connect(crossfadePlayer.sourceMixer, to: mainMixer, format: fmt)
        engine.connect(stemVocals.sourceMixer, to: mainMixer, format: fmt)
        engine.connect(stemInstrumental.sourceMixer, to: instEQ, format: fmt)
        engine.connect(instEQ, to: mainMixer, format: fmt)
        engine.connect(mainMixer, to: userEQ, format: fmt)
        engine.connect(userEQ, to: engine.mainMixerNode, format: fmt)

        crossfadePlayer.volume = 0
        stemVocals.volume = 0
        stemInstrumental.volume = 0

        for i in 0 ..< 10 {
            let band = userEQ.bands[i]
            band.filterType = .parametric
            band.frequency = AVEnginePlayback.bandFrequencies[i]
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
        userEQ.bypass = true

        let instBand = instEQ.bands[0]
        instBand.filterType = .lowShelf
        instBand.frequency = 250
        instBand.bandwidth = 1.0
        instBand.gain = 0
        instBand.bypass = true
        instEQ.bypass = true

        for player in [mainPlayer, crossfadePlayer] {
            player.completionHandler = { [weak self, weak player] in
                guard let self, let player else { return }
                // Only the deck currently designated as main can end a song.
                // The outgoing deck is stopped after a crossfade and must not
                // advance the queue.
                if self.mainPlayer === player, self.mode == .single {
                    self.onPlaybackEnded?()
                }
            }
        }
        stemInstrumental.completionHandler = { [weak self] in
            guard let self else { return }
            if self.mode == .aiStems { self.onPlaybackEnded?() }
        }

        engine.isAutoShutdownEnabled = false
        engine.prepare()
        do { try engine.start() } catch {
            DebugLogger.log("Audio engine start failed: \(error)", category: .playback)
            onPlaybackError?(error)
        }

        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.handleEngineConfigurationChange()
                }
            }
        }
    }

    isolated deinit {
        if let engineConfigObserver {
            NotificationCenter.default.removeObserver(engineConfigObserver)
        }
        crossfadeTimer?.cancel()
        crossfadeTimer = nil
        singleLoadTask?.cancel()
        stemsLoadTask?.cancel()
        switchToStemsLoadTask?.cancel()
        crossfadePreloadTask?.cancel()
        mainPlayer.playerNode.stop()
        crossfadePlayer.playerNode.stop()
        stemVocals.playerNode.stop()
        stemInstrumental.playerNode.stop()
        engine.stop()
    }

    func startEngineIfNeeded() {
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
                DebugLogger.log("Audio engine restarted", category: .playback)
            } catch {
                DebugLogger.log("Audio engine restart failed: \(error)", category: .playback)
                onPlaybackError?(error)
            }
        }
    }

    private func handleEngineConfigurationChange() {
        DebugLogger.log("Audio engine configuration changed, isRunning=\(engine.isRunning)", category: .playback)
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
                DebugLogger.log("Audio engine restarted after configuration change", category: .playback)
            } catch {
                DebugLogger.log("Audio engine restart failed after config change: \(error)", category: .playback)
                onPlaybackError?(error)
                return
            }
        }
        onEngineConfigurationChange?()
    }

    nonisolated static func hasValidAudioHeader(at url: URL) -> Bool {
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

    private func applyMedia(_ file: AVAudioFile, to player: SimpleAudioPlayer) throws {
        try player.load(file: file)
        engine.disconnectNodeOutput(player.playerNode)
        engine.connect(
            player.playerNode,
            to: player.sourceMixer,
            format: file.processingFormat
        )
    }

    private nonisolated static func loadMedia(
        url: URL,
        intent _: MediaLoadIntent
    ) throws -> AVAudioFile {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: url.path) else {
            let err = NSError(
                domain: NSOSStatusErrorDomain, code: 1_685_348_671,
                userInfo: [NSLocalizedDescriptionKey: "Audio file not found: \(url.lastPathComponent)"]
            )
            throw err
        }
        try Task.checkCancellation()
        return try AVAudioFile(forReading: url)
    }

    nonisolated static var transitionTimerInterval: TimeInterval {
        let ticksPerSecond = isResourceConstrained
            ? constrainedTransitionTicksPerSecond : defaultTransitionTicksPerSecond
        return 1.0 / ticksPerSecond
    }

    private nonisolated static var isResourceConstrained: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.physicalMemory <= constrainedMemoryThreshold
    }

    private func safePlay(_ player: SimpleAudioPlayer, from position: TimeInterval) {
        safePlay(player, from: position, at: nil)
    }

    private func safePlay(
        _ player: SimpleAudioPlayer,
        from position: TimeInterval,
        at startTime: AVAudioTime?
    ) {
        player.stop()
        player.playerNode.reset()
        let dur = player.duration
        guard dur.isFinite, dur > 0 else {
            player.play()
            return
        }
        guard position.isFinite, position >= 0 else {
            player.play()
            return
        }
        let clamped = min(position, max(0, dur - 0.25))
        if clamped < 0.05 {
            if let startTime {
                player.play(from: 0, at: startTime)
            } else {
                player.play()
            }
        } else {
            player.play(from: clamped, at: startTime)
        }
    }

    private func synchronizedStartTime(leadTime: TimeInterval = 0.08) -> AVAudioTime {
        AVAudioTime.now().offset(seconds: leadTime)
    }

    private func synchronizedPlay(
        mainPos: TimeInterval,
        stemPos: TimeInterval,
        when: AVAudioTime? = nil
    ) {
        let startTime = when ?? synchronizedStartTime()
        mainPlayer.stop()
        stemVocals.stop()
        stemInstrumental.stop()
        mainPlayer.playerNode.reset()
        stemVocals.playerNode.reset()
        stemInstrumental.playerNode.reset()
        mainPlayer.play(from: mainPos, at: startTime)
        stemVocals.play(from: stemPos, at: startTime)
        stemInstrumental.play(from: stemPos, at: startTime)
    }

    private func resetCrossfadePlayback() {
        cancelCrossfadeLoadTasks()
        crossfadeRampGeneration &+= 1
        crossfadeTimer?.cancel()
        crossfadeTimer = nil
        pendingCrossfadeURL = nil
        preloadedCrossfadeURL = nil
        isCrossfading = false
        crossfadeStartMainVol = 1.0
        crossfadeStartVocalsVol = 0
        crossfadeStartInstrumentalVol = 0
        releasePlayerMedia(crossfadePlayer)
    }

    func play(url: URL, startAt: TimeInterval = 0, onReady: (() -> Void)? = nil) {
        DebugLogger.log("Play single: \(url.lastPathComponent)", category: .playback)
        _paused = false
        suppressionToken &+= 1
        let token = suppressionToken
        cancelPrimaryLoadTasks()
        let loadGeneration = primaryLoadGeneration
        resetCrossfadePlayback()
        stopAllStems(releasingMedia: true)
        releasePlayerMedia(mainPlayer, resetVolumeTo: 1)
        let loadTask = Task.detached(priority: .userInitiated) {
            LoadedMediaTransfer(value: try Self.loadMedia(url: url, intent: .immediatePlayback))
        }
        singleLoadTask = loadTask
        Task {
            do {
                let media = try await loadTask.value.value
                guard self.suppressionToken == token, self.primaryLoadGeneration == loadGeneration else {
                    return
                }
                try self.applyMedia(media, to: self.mainPlayer)
                self.singleLoadTask = nil
                self.currentURL = url
                self.mode = .single
                self.aiStartOffset = 0
                self.mainPlayer.volume = 1
                self.resetInstrumentalEQ()
                self.startEngineIfNeeded()
                self.safePlay(self.mainPlayer, from: startAt)
                onReady?()
            } catch is CancellationError {
                guard self.primaryLoadGeneration == loadGeneration else { return }
                self.singleLoadTask = nil
            } catch {
                guard self.suppressionToken == token, self.primaryLoadGeneration == loadGeneration else {
                    return
                }
                self.singleLoadTask = nil
                self.onPlaybackError?(error)
            }
        }
    }

    func playStems(
        originalURL: URL, vocalsURL: URL, instrumentsURL: URL,
        startOffset: TimeInterval, startAt: TimeInterval = 0,
        onReady: (() -> Void)? = nil
    ) {
        DebugLogger.log(
            "Play stems: vocals=\(vocalsURL.lastPathComponent), inst=\(instrumentsURL.lastPathComponent)",
            category: .playback
        )
        _paused = false
        suppressionToken &+= 1
        let token = suppressionToken
        cancelPrimaryLoadTasks()
        let loadGeneration = primaryLoadGeneration
        resetCrossfadePlayback()
        stopAllStems(releasingMedia: true)
        releasePlayerMedia(mainPlayer, resetVolumeTo: 1)
        let loadTask = Task.detached(priority: .userInitiated) {
            let m = try Self.loadMedia(url: originalURL, intent: .immediatePlayback)
            try Task.checkCancellation()
            let v = try Self.loadMedia(url: vocalsURL, intent: .immediatePlayback)
            try Task.checkCancellation()
            let i = try Self.loadMedia(url: instrumentsURL, intent: .immediatePlayback)
            return LoadedMediaTransfer(value: (m, v, i))
        }
        stemsLoadTask = loadTask
        Task {
            do {
                let media = try await loadTask.value.value
                guard self.suppressionToken == token, self.primaryLoadGeneration == loadGeneration else {
                    return
                }
                try self.applyMedia(media.0, to: self.mainPlayer)
                self.currentURL = originalURL
                try self.applyMedia(media.1, to: self.stemVocals)
                try self.applyMedia(media.2, to: self.stemInstrumental)
                self.stemsLoadTask = nil

                self.aiStartOffset = max(0, startOffset)
                self.mode = .aiStems
                self.resetInstrumentalEQ()
                self.startEngineIfNeeded()
                var stemPos = max(0, startAt - self.aiStartOffset)
                let stemDur = self.stemInstrumental.duration
                if stemDur.isFinite, stemDur > 0.5 {
                    stemPos = min(stemPos, stemDur - 0.5)
                } else if stemDur.isFinite, stemDur > 0 {
                    stemPos = 0
                }
                let mainDur = self.mainPlayer.duration
                var mainPos = max(0, startAt)
                if mainDur.isFinite, mainDur > 0.5 {
                    mainPos = min(mainPos, mainDur - 0.5)
                }
                self.mainPlayer.volume = 1
                self.stemVocals.volume = 0
                self.stemInstrumental.volume = 0
                self.synchronizedPlay(mainPos: mainPos, stemPos: stemPos)
                onReady?()
            } catch is CancellationError {
                guard self.primaryLoadGeneration == loadGeneration else { return }
                self.stemsLoadTask = nil
            } catch {
                guard self.suppressionToken == token, self.primaryLoadGeneration == loadGeneration else {
                    return
                }
                self.stemsLoadTask = nil
                self.stopAllStems(releasingMedia: true)
                self.onPlaybackError?(error)
            }
        }
    }

    func switchToStems(
        vocalsURL: URL, instrumentsURL: URL,
        startOffset: TimeInterval,
        onReady: (() -> Void)? = nil
    ) {
        DebugLogger.log("Switching to stems at offset \(startOffset)", category: .playback)
        _paused = false
        suppressionToken &+= 1
        let token = suppressionToken
        cancelPrimaryLoadTasks()
        let loadGeneration = primaryLoadGeneration
        resetCrossfadePlayback()
        stopAllStems(releasingMedia: true)
        let loadTask = Task.detached(priority: .userInitiated) {
            let v = try Self.loadMedia(url: vocalsURL, intent: .immediatePlayback)
            try Task.checkCancellation()
            let i = try Self.loadMedia(url: instrumentsURL, intent: .immediatePlayback)
            return LoadedMediaTransfer(value: (v, i))
        }
        switchToStemsLoadTask = loadTask
        Task {
            do {
                let media = try await loadTask.value.value
                guard self.suppressionToken == token, self.primaryLoadGeneration == loadGeneration else {
                    return
                }
                try self.applyMedia(media.0, to: self.stemVocals)
                try self.applyMedia(media.1, to: self.stemInstrumental)
                self.switchToStemsLoadTask = nil

                self.aiStartOffset = max(0, startOffset)
                self.mode = .aiStems
                self.startEngineIfNeeded()
                let pos = self.mainPlayer.currentTime
                var stemPos = max(0, pos - startOffset)
                if !stemPos.isFinite || stemPos < 0 { stemPos = 0 }
                let stemDur = self.stemInstrumental.duration
                if stemDur.isFinite, stemDur > 0.5 {
                    stemPos = min(stemPos, stemDur - 0.5)
                } else if stemDur.isFinite, stemDur > 0 {
                    stemPos = 0
                }
                let mainDur = self.mainPlayer.duration
                var mainPos = max(0, pos)
                if mainDur.isFinite, mainDur > 0.5 {
                    mainPos = min(mainPos, mainDur - 0.5)
                }
                self.mainPlayer.volume = 1
                self.stemVocals.volume = 0
                self.stemInstrumental.volume = 0
                self.synchronizedPlay(mainPos: mainPos, stemPos: stemPos)
                onReady?()
            } catch is CancellationError {
                guard self.primaryLoadGeneration == loadGeneration else { return }
                self.switchToStemsLoadTask = nil
            } catch {
                guard self.suppressionToken == token, self.primaryLoadGeneration == loadGeneration else {
                    return
                }
                self.switchToStemsLoadTask = nil
                self.stopAllStems(releasingMedia: true)
                self.onPlaybackError?(error)
            }
        }
    }

    func revertToMain() {
        guard mode == .aiStems else { return }
        DebugLogger.log("Reverting to main player", category: .playback)
        let wasPaused = _paused
        _paused = false
        if currentURL != nil {
            mainPlayer.volume = 1
            stopAllStems()
            mode = .single
            aiStartOffset = 0
            resetInstrumentalEQ()
            if wasPaused {
                mainPlayer.pause()
                _paused = true
            }
            return
        }
        var pos = stemInstrumental.currentTime + aiStartOffset
        if !pos.isFinite || pos < 0 { pos = 0 }
        suppressionToken &+= 1
        resetCrossfadePlayback()
        let dur = mainPlayer.duration.isFinite && mainPlayer.duration > 0
            ? mainPlayer.duration : (stemInstrumental.duration + aiStartOffset)
        let clampedPos = min(pos, max(0, dur - 0.25))
        mainPlayer.volume = 1
        resetInstrumentalEQ()
        startEngineIfNeeded()
        safePlay(mainPlayer, from: clampedPos)
        stopAllStems()
        mode = .single
        aiStartOffset = 0
    }

    private func stopAllStems(releasingMedia: Bool = false) {
        stemVocals.stop()
        stemInstrumental.stop()
        stemVocals.volume = 0
        stemInstrumental.volume = 0
        if releasingMedia {
            releasePlayerMedia(stemVocals)
            releasePlayerMedia(stemInstrumental)
        }
    }

    func setStemVolumes(vocals: Float, instrumental: Float) {
        stemVocals.volume = max(0, min(2, vocals))
        stemInstrumental.volume = max(0, min(2, instrumental))
    }

    func setAIMix(main: Float, vocals: Float, instrumental: Float) {
        mainPlayer.volume = max(0, min(1, main))
        setStemVolumes(vocals: vocals, instrumental: instrumental)
    }

    func setInstrumentalEQGain(dB: Float) {
        let band = instEQ.bands[0]
        band.gain = dB
        let active = dB > 0.01
        band.bypass = !active
        instEQ.bypass = !active
    }

    func resetInstrumentalEQ() {
        setInstrumentalEQGain(dB: 0)
    }

    func switchToFinalFile(url: URL) {
        currentURL = url
    }

    var currentTime: TimeInterval {
        mainPlayer.currentTime
    }

    var duration: TimeInterval {
        mainPlayer.duration
    }

    var isPlaying: Bool {
        if _paused { return false }
        return mainPlayer.isPlaying
    }

    func pause() {
        _paused = true
        suppressionToken &+= 1
        if mode == .aiStems {
            mainPlayer.pause()
            stemVocals.pause()
            stemInstrumental.pause()
        } else {
            mainPlayer.pause()
        }
        // File playback uses AVAudioEngine rather than AVPlayer. Pausing only the
        // AVAudioPlayerNode leaves the engine running, and iOS Control Center can
        // keep treating the session as actively playing even when Now Playing rate
        // is 0.0. Pausing the engine makes app, lock-screen, and Control Center
        // play/pause state agree; resume() restarts it through startEngineIfNeeded().
        engine.pause()
    }

    func resume() {
        _paused = false
        startEngineIfNeeded()
        if mode == .aiStems {
            mainPlayer.play()
            stemVocals.play()
            stemInstrumental.play()
        } else {
            mainPlayer.play()
        }
    }

    func stop() {
        DebugLogger.log("Playback stop", category: .playback)
        _paused = false
        suppressionToken &+= 1
        cancelPrimaryLoadTasks()
        resetCrossfadePlayback()
        releasePlayerMedia(mainPlayer, resetVolumeTo: 1)
        stopAllStems(releasingMedia: true)
        currentURL = nil
        aiStartOffset = 0
        mode = .single
        resetInstrumentalEQ()
    }

    @discardableResult
    func seek(to seconds: TimeInterval) -> Bool {
        guard seconds.isFinite else { return true }
        if mode == .aiStems {
            let stemTarget = seconds - aiStartOffset
            if stemTarget < 0 { return false }
            let dur = stemInstrumental.duration
            guard dur.isFinite, dur > 0 else { return true }
            let upper = dur - 0.5
            guard upper > 0 else { return true }
            let target = max(0, min(stemTarget, upper))
            suppressionToken &+= 1
            let when = synchronizedStartTime()
            synchronizedPlay(mainPos: seconds, stemPos: target, when: when)
            return true
        }
        let dur = mainPlayer.duration
        guard dur.isFinite, dur > 0 else { return true }
        let upper = dur - 0.5
        guard upper > 0 else { return true }
        let target = max(0, min(seconds, upper))
        suppressionToken &+= 1
        safePlay(mainPlayer, from: target)
        return true
    }

    func setEQEnabled(_ on: Bool) {
        userEQ.bypass = !on
    }

    func setEQGains(_ gains: [Float]) {
        for i in 0 ..< min(gains.count, userEQ.bands.count) {
            userEQ.bands[i].gain = gains[i]
        }
    }

    func setMasterVolume(_ v: Float) {
        mainMixer.outputVolume = max(0, min(1, v))
    }

    func preloadCrossfade(url: URL) {
        guard !isCrossfading else { return }
        guard preloadedCrossfadeURL != url, crossfadePreloadURL != url else { return }
        DebugLogger.log(
            "Preloading crossfade media for \(url.lastPathComponent)", category: .playback
        )
        crossfadePreloadTask?.cancel()
        crossfadeLoadGeneration &+= 1
        let loadGeneration = crossfadeLoadGeneration
        crossfadePreloadURL = url
        let loadTask = Task.detached(priority: .utility) {
            LoadedMediaTransfer(value: try Self.loadMedia(url: url, intent: .prefetch))
        }
        crossfadePreloadTask = loadTask
        Task {
            do {
                let media = try await loadTask.value.value
                guard self.crossfadeLoadGeneration == loadGeneration else { return }
                try self.applyMedia(media, to: self.crossfadePlayer)
                self.preparedCrossfadeMedia = media
                self.crossfadePreloadTask = nil
                self.crossfadePreloadURL = nil
                self.preloadedCrossfadeURL = url
                self.crossfadePlayer.volume = 0
                DebugLogger.log(
                    "Crossfade preload ready for \(url.lastPathComponent): \(Self.describeMedia(media))",
                    category: .playback
                )
            } catch is CancellationError {
                guard self.crossfadeLoadGeneration == loadGeneration else { return }
                self.crossfadePreloadTask = nil
                self.crossfadePreloadURL = nil
                self.preloadedCrossfadeURL = nil
                self.preparedCrossfadeMedia = nil
                DebugLogger.log(
                    "Crossfade preload cancelled for \(url.lastPathComponent)", category: .playback
                )
            } catch {
                guard self.crossfadeLoadGeneration == loadGeneration else { return }
                self.crossfadePreloadTask = nil
                self.crossfadePreloadURL = nil
                self.preloadedCrossfadeURL = nil
                self.preparedCrossfadeMedia = nil
                DebugLogger.log(
                    "Crossfade preload failed for \(url.lastPathComponent): \(error)",
                    category: .playback
                )
            }
        }
    }

    func beginCrossfade(url: URL, duration: TimeInterval, ramp: RampStyle) {
        let alreadyPreloaded = (preloadedCrossfadeURL == url)
        DebugLogger.log(
            "Crossfade begin: \(url.lastPathComponent), duration=\(duration), ramp=\(ramp), alreadyPreloaded=\(alreadyPreloaded), mode=\(mode)",
            category: .playback
        )
        let retainedPreparedMedia = alreadyPreloaded ? preparedCrossfadeMedia : nil

        crossfadeRampGeneration &+= 1
        crossfadeTimer?.cancel()
        crossfadeTimer = nil
        if !alreadyPreloaded {
            crossfadePreloadTask?.cancel()
        }
        crossfadeLoadGeneration &+= 1
        let loadGeneration = crossfadeLoadGeneration
        if !alreadyPreloaded {
            crossfadePreloadURL = nil
            preloadedCrossfadeURL = nil
            preparedCrossfadeMedia = nil
        } else {
            preparedCrossfadeMedia = retainedPreparedMedia
        }
        if isCrossfading {
            isCrossfading = false
            if !alreadyPreloaded {
                crossfadePlayer.stop()
                crossfadePlayer.playerNode.reset()
                crossfadePlayer.volume = 0
            }
            if mode == .single {
                mainPlayer.volume = 1.0
            } else if mode == .aiStems {
                mainPlayer.volume = crossfadeStartMainVol
                setStemVolumes(
                    vocals: crossfadeStartVocalsVol,
                    instrumental: crossfadeStartInstrumentalVol
                )
            }
        }

        pendingCrossfadeURL = url

        let token = suppressionToken
        Task {
            do {
                try await self.ensureCrossfadePrepared(
                    for: url, token: token, loadGeneration: loadGeneration
                )
                guard self.suppressionToken == token, self.crossfadeLoadGeneration == loadGeneration else {
                    return
                }
                let fadeDuration = max(0.5, duration)
                self.isCrossfading = true
                self.crossfadeStartMainVol = self.mainPlayer.volume
                self.crossfadeStartVocalsVol = self.stemVocals.volume
                self.crossfadeStartInstrumentalVol = self.stemInstrumental.volume
                self.crossfadePlayer.volume = 0
                self.startEngineIfNeeded()
                let playbackLeadTime: TimeInterval = 0.08
                let scheduledStart = self.synchronizedStartTime(leadTime: playbackLeadTime)
                self.crossfadePlayer.play(from: 0, at: scheduledStart)
                self.onCrossfadeStarted?()
                DebugLogger.log(
                    "Crossfade playback started for \(url.lastPathComponent), source=\(Self.describeMedia(self.preparedCrossfadeMedia))",
                    category: .playback
                )
                self.crossfadeRampGeneration &+= 1
                let rampGeneration = self.crossfadeRampGeneration
                let startUptime = ProcessInfo.processInfo.systemUptime + playbackLeadTime
                let mainNode = self.mainPlayer.playerNode
                let vocalsNode = self.stemVocals.playerNode
                let instrumentalNode = self.stemInstrumental.playerNode
                let incomingNode = self.crossfadePlayer.playerNode
                let fadesStems = self.mode == .aiStems
                let startMainVolume = self.crossfadeStartMainVol
                let startVocalsVolume = self.crossfadeStartVocalsVol
                let startInstrumentalVolume = self.crossfadeStartInstrumentalVol
                let timer = DispatchSource.makeTimerSource(queue: Self.crossfadeRampQueue)
                timer.schedule(
                    deadline: .now() + playbackLeadTime,
                    repeating: Self.transitionTimerInterval,
                    leeway: .milliseconds(2)
                )
                var completionDispatched = false
                timer.setEventHandler { [weak self] in
                    let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startUptime)
                    let t = Float(min(1, elapsed / fadeDuration))
                    let outVolume: Float
                    let inVolume: Float
                    switch ramp {
                    case .equalPower:
                        outVolume = cos(t * .pi / 2)
                        inVolume = sin(t * .pi / 2)
                    case .linear:
                        outVolume = 1 - t
                        inVolume = t
                    }
                    mainNode.volume = max(0, startMainVolume * outVolume)
                    if fadesStems {
                        vocalsNode.volume = max(0, startVocalsVolume * outVolume)
                        instrumentalNode.volume = max(0, startInstrumentalVolume * outVolume)
                    }
                    incomingNode.volume = max(0, inVolume)
                    guard t >= 1, !completionDispatched else { return }
                    completionDispatched = true
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self,
                                  self.crossfadeRampGeneration == rampGeneration,
                                  self.isCrossfading
                            else { return }
                            self.finalizeCrossfade()
                        }
                    }
                }
                self.crossfadeTimer = timer
                timer.resume()
            } catch is CancellationError {
                guard self.crossfadeLoadGeneration == loadGeneration else { return }
                self.crossfadePreloadTask = nil
                self.pendingCrossfadeURL = nil
                DebugLogger.log(
                    "Crossfade begin cancelled for \(url.lastPathComponent)", category: .playback
                )
            } catch {
                guard self.suppressionToken == token, self.crossfadeLoadGeneration == loadGeneration else {
                    return
                }
                self.crossfadePreloadTask = nil
                self.isCrossfading = false
                self.pendingCrossfadeURL = nil
                self.releasePlayerMedia(self.crossfadePlayer)
                DebugLogger.log(
                    "Crossfade begin failed for \(url.lastPathComponent): \(error)", category: .playback
                )
                self.onPlaybackError?(error)
            }
        }
    }

    func cancelCrossfade() {
        cancelCrossfadeLoadTasks()
        crossfadeRampGeneration &+= 1
        crossfadeTimer?.cancel()
        crossfadeTimer = nil
        preloadedCrossfadeURL = nil
        pendingCrossfadeURL = nil
        guard isCrossfading else {
            releasePlayerMedia(crossfadePlayer)
            return
        }
        isCrossfading = false
        releasePlayerMedia(crossfadePlayer)
        if mode == .aiStems {
            mainPlayer.volume = crossfadeStartMainVol
            setStemVolumes(
                vocals: crossfadeStartVocalsVol,
                instrumental: crossfadeStartInstrumentalVol
            )
        } else {
            mainPlayer.volume = 1.0
        }
    }

    private func finalizeCrossfade() {
        crossfadeRampGeneration &+= 1
        crossfadeTimer?.cancel()
        crossfadeTimer = nil
        isCrossfading = false

        suppressionToken &+= 1
        let completedURL = pendingCrossfadeURL
        DebugLogger.log(
            "Finalizing crossfade by swapping decks pending=\(completedURL?.lastPathComponent ?? "nil"), time=\(crossfadePlayer.currentTime)",
            category: .playback
        )

        // Keep the incoming node and its scheduled file playing. Reloading it
        // into the outgoing node used to allocate duplicate media and created a
        // teardown completion race. Deck identity is an implementation detail,
        // so swapping the references is the seamless handoff.
        let outgoingPlayer = mainPlayer
        mainPlayer = crossfadePlayer
        crossfadePlayer = outgoingPlayer
        mainPlayer.volume = 1

        cancelCrossfadeLoadTasks()
        releasePlayerMedia(crossfadePlayer)
        if mode == .aiStems {
            stopAllStems(releasingMedia: true)
        }
        mode = .single
        aiStartOffset = 0
        resetInstrumentalEQ()
        currentURL = completedURL
        pendingCrossfadeURL = nil
        preloadedCrossfadeURL = nil
        onCrossfadeCompleted?()
    }

    private func cancelPrimaryLoadTasks() {
        primaryLoadGeneration &+= 1
        singleLoadTask?.cancel()
        stemsLoadTask?.cancel()
        switchToStemsLoadTask?.cancel()
        singleLoadTask = nil
        stemsLoadTask = nil
        switchToStemsLoadTask = nil
    }

    private func cancelCrossfadeLoadTasks() {
        crossfadeLoadGeneration &+= 1
        crossfadePreloadTask?.cancel()
        crossfadePreloadTask = nil
        crossfadePreloadURL = nil
        preparedCrossfadeMedia = nil
    }

    private func releasePlayerMedia(_ player: SimpleAudioPlayer, resetVolumeTo volume: Float = 0) {
        player.unload()
        player.playerNode.reset()
        player.volume = volume
    }

    private(set) var pendingCrossfadeURL: URL?

    var isCrossfadePending: Bool { pendingCrossfadeURL != nil }

    private var preloadedCrossfadeURL: URL?
    private var crossfadePreloadURL: URL?

    private var crossfadeStartMainVol: Float = 1.0
    private var crossfadeStartVocalsVol: Float = 0
    private var crossfadeStartInstrumentalVol: Float = 0

    private func ensureCrossfadePrepared(
        for url: URL,
        token: UInt64,
        loadGeneration: UInt64
    ) async throws {
        if preloadedCrossfadeURL == url { return }

        if crossfadePreloadURL == url, let existingTask = crossfadePreloadTask {
            DebugLogger.log(
                "Awaiting in-flight crossfade preload for \(url.lastPathComponent)", category: .playback
            )
            let media = try await existingTask.value.value
            guard suppressionToken == token, crossfadeLoadGeneration == loadGeneration else { return }
            try applyMedia(media, to: crossfadePlayer)
            preparedCrossfadeMedia = media
            crossfadePreloadTask = nil
            crossfadePreloadURL = nil
            preloadedCrossfadeURL = url
            crossfadePlayer.volume = 0
            DebugLogger.log(
                "Reused in-flight preload for \(url.lastPathComponent): \(Self.describeMedia(media))",
                category: .playback
            )
            return
        }

        crossfadePreloadTask?.cancel()
        crossfadePreloadURL = url
        DebugLogger.log(
            "Loading crossfade media on demand for \(url.lastPathComponent)", category: .playback
        )
        let loadTask = Task.detached(priority: .userInitiated) {
            LoadedMediaTransfer(value: try Self.loadMedia(url: url, intent: .prefetch))
        }
        crossfadePreloadTask = loadTask
        let media = try await loadTask.value.value
        guard suppressionToken == token, crossfadeLoadGeneration == loadGeneration else { return }
        try applyMedia(media, to: crossfadePlayer)
        preparedCrossfadeMedia = media
        crossfadePreloadTask = nil
        crossfadePreloadURL = nil
        preloadedCrossfadeURL = url
        crossfadePlayer.volume = 0
        DebugLogger.log(
            "On-demand crossfade media ready for \(url.lastPathComponent): \(Self.describeMedia(media))",
            category: .playback
        )
    }

    private static func describeMedia(_ media: LoadedMedia?) -> String {
        guard let media else { return "none" }
        let format = media.processingFormat
        return "file(\(Int(format.sampleRate))Hz/\(format.channelCount)ch)"
    }
}
