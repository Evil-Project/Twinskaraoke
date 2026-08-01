import AVFoundation
import Foundation

enum AVEnginePlaybackMode { case single, aiStems }

/// Moves freshly loaded, uniquely referenced audio media out of a background
/// loading task; AVAudioFile/AVAudioPCMBuffer are not Sendable but the loader
/// hands over its only reference.
private nonisolated struct LoadedMediaTransfer<Value>: @unchecked Sendable {
    let value: Value
}

nonisolated struct PlaybackScheduleGate: Sendable {
    private(set) var currentGeneration: UInt64 = 0

    mutating func beginSchedule() -> UInt64 {
        currentGeneration &+= 1
        return currentGeneration
    }

    mutating func invalidate() {
        currentGeneration &+= 1
    }

    mutating func consume(_ generation: UInt64) -> Bool {
        guard generation == currentGeneration else { return false }
        currentGeneration &+= 1
        return true
    }
}

nonisolated struct TransitionRampCompletionGate: Sendable {
    private(set) var currentGeneration: UInt64 = 0

    mutating func begin() -> UInt64 {
        currentGeneration &+= 1
        return currentGeneration
    }

    func owns(_ generation: UInt64) -> Bool {
        generation == currentGeneration
    }

    mutating func invalidate() {
        currentGeneration &+= 1
    }

    mutating func consume(_ generation: UInt64) -> Bool {
        guard owns(generation) else { return false }
        currentGeneration &+= 1
        return true
    }
}

nonisolated struct StemLoadOwnershipGate: Sendable {
    enum Recovery: Sendable, Equatable {
        case preserveMainPlayback
        case reloadOriginal
    }

    struct Token: Sendable, Equatable {
        fileprivate let generation: UInt64
        let recovery: Recovery
    }

    private(set) var currentGeneration: UInt64 = 0
    private(set) var activeToken: Token?

    mutating func begin(recovery: Recovery) -> Token {
        currentGeneration &+= 1
        let token = Token(generation: currentGeneration, recovery: recovery)
        activeToken = token
        return token
    }

    func owns(_ token: Token) -> Bool {
        activeToken == token
    }

    mutating func consume(_ token: Token) -> Bool {
        guard owns(token) else { return false }
        currentGeneration &+= 1
        activeToken = nil
        return true
    }

    @discardableResult
    mutating func cancel() -> Recovery? {
        let recovery = activeToken?.recovery
        currentGeneration &+= 1
        activeToken = nil
        return recovery
    }
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

final class SimpleAudioPlayer {
    let playerNode = AVAudioPlayerNode()
    // Invoked from the audio render callback thread, hence @Sendable and
    // accessible off the main actor.
    nonisolated(unsafe) var completionHandler: (() -> Void)?

    private var loadedFile: AVAudioFile?
    private var loadedBuffer: AVAudioPCMBuffer?
    private var seekOffset: TimeInterval = 0
    private var pausedPosition: TimeInterval?
    private var _isPaused = false
    private var scheduleGate = PlaybackScheduleGate()

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    var duration: TimeInterval {
        if let file = loadedFile {
            guard file.processingFormat.sampleRate > 0 else { return 0 }
            return Double(file.length) / file.processingFormat.sampleRate
        }
        if let buffer = loadedBuffer {
            guard buffer.format.sampleRate > 0 else { return 0 }
            return Double(buffer.frameLength) / buffer.format.sampleRate
        }
        return 0
    }

    var scheduleGenerationForTesting: UInt64 {
        scheduleGate.currentGeneration
    }

    var loadedFileFormatForTesting: AVAudioFormat? {
        loadedFile?.processingFormat
    }

    func deliverCompletionForTesting(scheduledGeneration: UInt64) {
        deliverCompletion(scheduledGeneration: scheduledGeneration)
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
        scheduleGate.invalidate()
        playerNode.stop()
        loadedFile = file
        loadedBuffer = nil
        seekOffset = 0
        pausedPosition = nil
        _isPaused = false
    }

    func load(buffer: AVAudioPCMBuffer) {
        scheduleGate.invalidate()
        playerNode.stop()
        loadedFile = nil
        loadedBuffer = buffer
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
        let generation = scheduleGate.beginSchedule()
        playerNode.stop()
        seekOffset = max(0, seconds)
        pausedPosition = nil

        let scheduled: Bool
        if let file = loadedFile {
            scheduled = scheduleFileSegment(file, at: time, generation: generation)
        } else if let buffer = loadedBuffer {
            scheduled = scheduleBufferSegment(buffer, at: time, generation: generation)
        } else {
            scheduled = false
        }

        guard scheduled else {
            deliverCompletion(scheduledGeneration: generation)
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
        scheduleGate.invalidate()
        playerNode.stop()
        _isPaused = false
        seekOffset = 0
        pausedPosition = nil
    }

    private func deliverCompletion(scheduledGeneration generation: UInt64) {
        guard scheduleGate.consume(generation) else { return }
        completionHandler?()
    }

    private func scheduleFileSegment(
        _ file: AVAudioFile,
        at time: AVAudioTime?,
        generation: UInt64
    ) -> Bool {
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekOffset * sampleRate)
        let remaining = AVAudioFrameCount(max(0, file.length - startFrame))
        guard remaining > 0 else { return false }
        playerNode.scheduleSegment(
            file, startingFrame: startFrame, frameCount: remaining, at: time,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            self?.deliverCompletion(scheduledGeneration: generation)
        }
        return true
    }

    private func scheduleBufferSegment(
        _ buffer: AVAudioPCMBuffer,
        at time: AVAudioTime?,
        generation: UInt64
    ) -> Bool {
        let sampleRate = buffer.format.sampleRate
        let startFrame = Int(seekOffset * sampleRate)
        let totalFrames = Int(buffer.frameLength)

        if startFrame <= 0 {
            playerNode.scheduleBuffer(
                buffer, at: time, completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                self?.deliverCompletion(scheduledGeneration: generation)
            }
            return true
        }

        guard startFrame < totalFrames else { return false }
        let remaining = totalFrames - startFrame
        if let sub = Self.sliceBuffer(buffer, fromFrame: startFrame, frameCount: remaining) {
            playerNode.scheduleBuffer(
                sub, at: time, completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                self?.deliverCompletion(scheduledGeneration: generation)
            }
            return true
        }
        return false
    }

    private static func sliceBuffer(
        _ buffer: AVAudioPCMBuffer, fromFrame start: Int, frameCount: Int
    ) -> AVAudioPCMBuffer? {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              !buffer.format.isInterleaved,
              let srcChannels = buffer.floatChannelData,
              let sub = AVAudioPCMBuffer(
                  pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let dstChannels = sub.floatChannelData
        else { return nil }
        sub.frameLength = AVAudioFrameCount(frameCount)
        let channelCount = Int(buffer.format.channelCount)
        let byteCount = frameCount * MemoryLayout<Float>.size
        for ch in 0 ..< channelCount {
            memcpy(dstChannels[ch], srcChannels[ch].advanced(by: start), byteCount)
        }
        return sub
    }
}

@MainActor
final class AVEnginePlayback {
    typealias Mode = AVEnginePlaybackMode
    typealias RampStyle = AVEnginePlaybackRampStyle
    private typealias LoadedMedia = (AVAudioFile?, AVAudioPCMBuffer?)
    private typealias LoadedStemPair = (LoadedMedia, LoadedMedia)
    private typealias LoadedStemTriple = (LoadedMedia, LoadedMedia, LoadedMedia)
    private enum MediaLoadIntent {
        case immediatePlayback
        case prefetch
    }

    private struct PendingStemLoadContext {
        let token: StemLoadOwnershipGate.Token
        let originalURL: URL?
        let startAt: TimeInterval
        let shouldPlay: @MainActor () -> Bool
        let onCancelled: @MainActor () -> Void
        let temporaryLease: TemporaryStemFileLease?
    }

    private let engine = AVAudioEngine()
    let mainPlayer = SimpleAudioPlayer()
    let crossfadePlayer = SimpleAudioPlayer()
    let stemVocals = SimpleAudioPlayer()
    let stemInstrumental = SimpleAudioPlayer()
    let instEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let mainMixer = AVAudioMixerNode()
    let userEQ = AVAudioUnitEQ(numberOfBands: 10)

    private(set) var mode: Mode = .single
    private(set) var currentURL: URL?
    private(set) var aiStartOffset: TimeInterval = 0

    private var suppressionToken: UInt64 = 0
    private var _paused: Bool = false

    private(set) var isCrossfading = false

    private var crossfadeTimer: Timer?
    private var crossfadeRampFallbackTask: Task<Void, Never>?
    private var crossfadeRampCompletionGate = TransitionRampCompletionGate()
    private var handoffBlendTimer: Timer?
    private var handoffBlendFallbackTask: Task<Void, Never>?
    private var handoffBlendCompletionGate = TransitionRampCompletionGate()
    private var singleLoadTask: Task<LoadedMediaTransfer<LoadedMedia>, Error>?
    private var stemsLoadTask: Task<LoadedMediaTransfer<LoadedStemTriple>, Error>?
    private var switchToStemsLoadTask: Task<LoadedMediaTransfer<LoadedStemPair>, Error>?
    private var crossfadePreloadTask: Task<LoadedMediaTransfer<LoadedMedia>, Error>?
    private var crossfadeFinalizeTask: Task<LoadedMediaTransfer<LoadedMedia>, Error>?
    private var primaryLoadGeneration: UInt64 = 0
    private var crossfadeLoadGeneration: UInt64 = 0
    private var stemLoadOwnership = StemLoadOwnershipGate()
    private var pendingStemLoadContext: PendingStemLoadContext?
    private var activeTemporaryStemLease: TemporaryStemFileLease?
    private var preparedCrossfadeMedia: LoadedMedia?

    private var crossfadeDuration: TimeInterval = 0

    private var crossfadeElapsed: TimeInterval = 0
    private var crossfadeStartTime: Date?

    private var crossfadeRamp: RampStyle = .equalPower

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

    private nonisolated static let standardSampleRate: Double = 44100
    private nonisolated static let constrainedMemoryThreshold: UInt64 = 4 * 1024 * 1024 * 1024
    private nonisolated static let constrainedPlaybackBufferLimitBytes: Int64 = 48 * 1024 * 1024
    private nonisolated static let defaultPlaybackBufferLimitBytes: Int64 = 96 * 1024 * 1024
    private nonisolated static let constrainedPrefetchBufferLimitBytes: Int64 = 24 * 1024 * 1024
    private nonisolated static let defaultPrefetchBufferLimitBytes: Int64 = 48 * 1024 * 1024
    private nonisolated static let constrainedTransitionTicksPerSecond: Double = 18
    private nonisolated static let defaultTransitionTicksPerSecond: Double = 24

    init() {
        let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.standardSampleRate,
            channels: 2, interleaved: false
        )!

        engine.attach(mainPlayer.playerNode)
        engine.attach(crossfadePlayer.playerNode)
        engine.attach(stemVocals.playerNode)
        engine.attach(stemInstrumental.playerNode)
        engine.attach(instEQ)
        engine.attach(mainMixer)
        engine.attach(userEQ)

        engine.connect(mainPlayer.playerNode, to: mainMixer, format: fmt)
        engine.connect(crossfadePlayer.playerNode, to: mainMixer, format: fmt)
        engine.connect(stemVocals.playerNode, to: mainMixer, format: fmt)
        engine.connect(stemInstrumental.playerNode, to: instEQ, format: fmt)
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

        mainPlayer.completionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self._paused, self.mode == .single else { return }
                self.onPlaybackEnded?()
            }
        }
        stemInstrumental.completionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self._paused, self.mode == .aiStems else { return }
                self.onPlaybackEnded?()
            }
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

    private func applyMedia(_ media: (AVAudioFile?, AVAudioPCMBuffer?), to player: SimpleAudioPlayer)
        throws
    {
        if let file = media.0 {
            try player.load(file: file)
        } else if let buffer = media.1 {
            player.load(buffer: buffer)
        }
    }

    private nonisolated static func loadMedia(url: URL, intent: MediaLoadIntent) throws -> (
        AVAudioFile?, AVAudioPCMBuffer?
    ) {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: url.path) else {
            let err = NSError(
                domain: NSOSStatusErrorDomain, code: 1_685_348_671,
                userInfo: [NSLocalizedDescriptionKey: "Audio file not found: \(url.lastPathComponent)"]
            )
            throw err
        }
        let headerOK = AVEnginePlayback.hasValidAudioHeader(at: url)
        if headerOK {
            try Task.checkCancellation()
            if let file = try? AVAudioFile(forReading: url) {
                let fmt = file.processingFormat
                if fmt.channelCount == 2, abs(fmt.sampleRate - standardSampleRate) < 1 {
                    return (file, nil)
                }
                if fmt.channelCount == 1 {
                    if let stereo = AVEnginePlayback.convertToStereo(
                        file: file, sourceURL: url, intent: intent
                    ) {
                        return (nil, stereo)
                    }
                }
            }
            try Task.checkCancellation()
            if let file = try? AVAudioFile(
                forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false
            ) {
                let fmt = file.processingFormat
                if fmt.channelCount == 2, abs(fmt.sampleRate - standardSampleRate) < 1 {
                    return (file, nil)
                }
                if fmt.channelCount == 1 {
                    if let stereo = AVEnginePlayback.convertToStereo(
                        file: file, sourceURL: url, intent: intent
                    ) {
                        return (nil, stereo)
                    }
                }
            }
        }
        try Task.checkCancellation()
        if let buffer = AVEnginePlayback.decodeFileToBuffer(url: url, intent: intent) {
            return (nil, buffer)
        }
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url)
        return (file, nil)
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

    private nonisolated static func maxBufferedPCMBytes(for intent: MediaLoadIntent) -> Int64 {
        switch intent {
        case .immediatePlayback:
            isResourceConstrained
                ? constrainedPlaybackBufferLimitBytes : defaultPlaybackBufferLimitBytes
        case .prefetch:
            isResourceConstrained
                ? constrainedPrefetchBufferLimitBytes : defaultPrefetchBufferLimitBytes
        }
    }

    private nonisolated static func estimatedDecodedPCMBytes(for url: URL) -> Int64? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        guard seconds.isFinite, seconds > 0 else { return nil }
        let bytesPerFrame = 2 * MemoryLayout<Float>.size
        let estimated = seconds * 44100 * Double(bytesPerFrame)
        guard estimated.isFinite, estimated > 0 else { return nil }
        return Int64(min(estimated.rounded(.up), Double(Int64.max)))
    }

    private nonisolated static func shouldDecodeEntireFileToBuffer(
        url: URL,
        intent: MediaLoadIntent
    ) -> Bool {
        guard let estimatedBytes = estimatedDecodedPCMBytes(for: url) else { return true }
        return estimatedBytes <= maxBufferedPCMBytes(for: intent)
    }

    private nonisolated static func decodeFileToBuffer(url: URL, intent: MediaLoadIntent)
        -> AVAudioPCMBuffer?
    {
        guard shouldDecodeEntireFileToBuffer(url: url, intent: intent) else {
            DebugLogger.log(
                "Skipping eager decode for \(url.lastPathComponent) due to memory budget",
                category: .playback
            )
            return nil
        }
        guard let inputFile = try? AVAudioFile(forReading: url) else { return nil }
        let inputFormat = inputFile.processingFormat
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { return nil }
        let inputFrames = inputFile.length
        guard inputFrames > 0 else { return nil }
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: standardSampleRate,
                channels: 2, interleaved: false
            )
        else { return nil }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let estimatedFrames =
            AVAudioFrameCount((Double(inputFrames) * ratio).rounded(.up)) + 8192
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: estimatedFrames)
        else { return nil }

        let readChunkFrames: AVAudioFrameCount = 16384
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if Task.isCancelled {
                outStatus.pointee = .endOfStream
                return nil
            }
            guard let chunk = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: readChunkFrames)
            else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try inputFile.read(into: chunk, frameCount: readChunkFrames)
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
            if chunk.frameLength == 0 {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return chunk
        }

        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer, error: &conversionError, withInputFrom: inputBlock
        )
        if Task.isCancelled { return nil }
        guard status != .error else {
            if let conversionError {
                DebugLogger.log(
                    "Audio decode conversion failed for \(url.lastPathComponent): \(conversionError)",
                    category: .playback
                )
            }
            return nil
        }
        return outputBuffer.frameLength > 0 ? outputBuffer : nil
    }

    private nonisolated static func convertToStereo(
        file: AVAudioFile,
        sourceURL: URL,
        intent: MediaLoadIntent
    ) -> AVAudioPCMBuffer? {
        let srcFormat = file.processingFormat
        guard srcFormat.channelCount == 1 else { return nil }
        guard abs(srcFormat.sampleRate - standardSampleRate) < 1 else { return nil }
        guard shouldDecodeEntireFileToBuffer(url: sourceURL, intent: intent) else {
            DebugLogger.log(
                "Skipping mono expansion for \(sourceURL.lastPathComponent) due to memory budget",
                category: .playback
            )
            return nil
        }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return nil }
        guard let monoBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount)
        else { return nil }
        do { try file.read(into: monoBuf) } catch { return nil }
        return monoToStereo(monoBuf)
    }

    private nonisolated static func monoToStereo(_ mono: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = mono.frameLength
        guard frames > 0,
              let stereoFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32, sampleRate: mono.format.sampleRate,
                  channels: 2, interleaved: false
              ),
              let stereo = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames)
        else { return nil }
        stereo.frameLength = frames
        guard let monoData = mono.floatChannelData?[0],
              let leftData = stereo.floatChannelData?[0],
              let rightData = stereo.floatChannelData?[1]
        else { return nil }
        let byteCount = Int(frames) * MemoryLayout<Float>.size
        memcpy(leftData, monoData, byteCount)
        memcpy(rightData, monoData, byteCount)
        return stereo
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
        cancelCrossfadeRamp()
        cancelHandoffBlend()
        pendingCrossfadeURL = nil
        preloadedCrossfadeURL = nil
        isCrossfading = false
        crossfadeDuration = 0
        crossfadeElapsed = 0
        crossfadeStartMainVol = 1.0
        crossfadeStartVocalsVol = 0
        crossfadeStartInstrumentalVol = 0
        releasePlayerMedia(crossfadePlayer)
    }

    private func cancelCrossfadeRamp() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeRampFallbackTask?.cancel()
        crossfadeRampFallbackTask = nil
        crossfadeRampCompletionGate.invalidate()
    }

    private func cancelHandoffBlend() {
        handoffBlendTimer?.invalidate()
        handoffBlendTimer = nil
        handoffBlendFallbackTask?.cancel()
        handoffBlendFallbackTask = nil
        handoffBlendCompletionGate.invalidate()
    }

    func play(
        url: URL,
        startAt: TimeInterval = 0,
        shouldPlay: @escaping @MainActor () -> Bool = { true },
        onReady: (() -> Void)? = nil
    ) {
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
                if !shouldPlay() { self.pause() }
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
        temporaryLease: TemporaryStemFileLease? = nil,
        shouldPlay: @escaping @MainActor () -> Bool = { true },
        isRequestValid: @escaping @MainActor () -> Bool = { true },
        onCancelled: @escaping @MainActor () -> Void = {},
        onReady: (() -> Void)? = nil
    ) {
        DebugLogger.log(
            "Play stems: vocals=\(vocalsURL.lastPathComponent), inst=\(instrumentsURL.lastPathComponent)",
            category: .playback
        )
        suppressionToken &+= 1
        let token = suppressionToken
        cancelPrimaryLoadTasks()
        let loadGeneration = primaryLoadGeneration
        let requestToken = stemLoadOwnership.begin(recovery: .reloadOriginal)
        pendingStemLoadContext = PendingStemLoadContext(
            token: requestToken,
            originalURL: originalURL,
            startAt: max(0, startAt),
            shouldPlay: shouldPlay,
            onCancelled: onCancelled,
            temporaryLease: temporaryLease
        )
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
                guard self.suppressionToken == token,
                      self.primaryLoadGeneration == loadGeneration,
                      self.stemLoadOwnership.owns(requestToken)
                else {
                    return
                }
                if !isRequestValid() {
                    try self.applyMedia(media.0, to: self.mainPlayer)
                    guard self.stemLoadOwnership.consume(requestToken) else { return }
                    self.clearPendingStemLoadContext(
                        for: requestToken,
                        notifyCancellation: true,
                        cleanupTemporaryLease: true
                    )
                    self.stemsLoadTask = nil
                    self.currentURL = originalURL
                    self.mode = .single
                    self.aiStartOffset = 0
                    self.mainPlayer.volume = 1
                    self.resetInstrumentalEQ()
                    self.startEngineIfNeeded()
                    self._paused = false
                    self.safePlay(self.mainPlayer, from: max(0, startAt))
                    if !shouldPlay() { self.pause() }
                    return
                }
                try self.applyMedia(media.0, to: self.mainPlayer)
                try self.applyMedia(media.1, to: self.stemVocals)
                try self.applyMedia(media.2, to: self.stemInstrumental)
                guard self.stemLoadOwnership.consume(requestToken) else { return }
                self.activeTemporaryStemLease = temporaryLease
                self.clearPendingStemLoadContext(for: requestToken)
                self.stemsLoadTask = nil

                self.currentURL = originalURL
                self.aiStartOffset = max(0, startOffset)
                self.mode = .aiStems
                self.resetInstrumentalEQ()
                self.startEngineIfNeeded()
                self._paused = false
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
                if !shouldPlay() { self.pause() }
                onReady?()
            } catch is CancellationError {
                guard self.primaryLoadGeneration == loadGeneration,
                      self.stemLoadOwnership.consume(requestToken)
                else { return }
                self.clearPendingStemLoadContext(
                    for: requestToken,
                    notifyCancellation: true,
                    cleanupTemporaryLease: true
                )
                self.stemsLoadTask = nil
            } catch {
                guard self.suppressionToken == token,
                      self.primaryLoadGeneration == loadGeneration,
                      self.stemLoadOwnership.consume(requestToken)
                else {
                    return
                }
                self.stemsLoadTask = nil
                self.stopAllStems(releasingMedia: true)
                self.clearPendingStemLoadContext(
                    for: requestToken,
                    cleanupTemporaryLease: true
                )
                self.onPlaybackError?(error)
            }
        }
    }

    func switchToStems(
        vocalsURL: URL, instrumentsURL: URL,
        startOffset: TimeInterval,
        temporaryLease: TemporaryStemFileLease? = nil,
        shouldPlay: @escaping @MainActor () -> Bool = { true },
        isRequestValid: @escaping @MainActor () -> Bool = { true },
        onCancelled: @escaping @MainActor () -> Void = {},
        onReady: (() -> Void)? = nil
    ) {
        DebugLogger.log("Switching to stems at offset \(startOffset)", category: .playback)
        suppressionToken &+= 1
        let token = suppressionToken
        cancelPrimaryLoadTasks()
        let loadGeneration = primaryLoadGeneration
        let requestToken = stemLoadOwnership.begin(recovery: .preserveMainPlayback)
        pendingStemLoadContext = PendingStemLoadContext(
            token: requestToken,
            originalURL: nil,
            startAt: 0,
            shouldPlay: shouldPlay,
            onCancelled: onCancelled,
            temporaryLease: temporaryLease
        )
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
                guard self.suppressionToken == token,
                      self.primaryLoadGeneration == loadGeneration,
                      self.stemLoadOwnership.owns(requestToken)
                else {
                    return
                }
                guard isRequestValid() else {
                    guard self.stemLoadOwnership.consume(requestToken) else { return }
                    self.switchToStemsLoadTask = nil
                    self.stopAllStems(releasingMedia: true)
                    self.clearPendingStemLoadContext(
                        for: requestToken,
                        notifyCancellation: true,
                        cleanupTemporaryLease: true
                    )
                    self.aiStartOffset = 0
                    self.mode = .single
                    self.resetInstrumentalEQ()
                    return
                }
                try self.applyMedia(media.0, to: self.stemVocals)
                try self.applyMedia(media.1, to: self.stemInstrumental)
                guard self.stemLoadOwnership.consume(requestToken) else { return }
                self.activeTemporaryStemLease = temporaryLease
                self.clearPendingStemLoadContext(for: requestToken)
                self.switchToStemsLoadTask = nil

                self.aiStartOffset = max(0, startOffset)
                self.mode = .aiStems
                self.startEngineIfNeeded()
                self._paused = false
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
                if !shouldPlay() { self.pause() }
                onReady?()
            } catch is CancellationError {
                guard self.primaryLoadGeneration == loadGeneration,
                      self.stemLoadOwnership.consume(requestToken)
                else { return }
                self.clearPendingStemLoadContext(
                    for: requestToken,
                    notifyCancellation: true,
                    cleanupTemporaryLease: true
                )
                self.switchToStemsLoadTask = nil
            } catch {
                guard self.suppressionToken == token,
                      self.primaryLoadGeneration == loadGeneration,
                      self.stemLoadOwnership.consume(requestToken)
                else {
                    return
                }
                self.switchToStemsLoadTask = nil
                self.stopAllStems(releasingMedia: true)
                self.clearPendingStemLoadContext(
                    for: requestToken,
                    cleanupTemporaryLease: true
                )
                self.onPlaybackError?(error)
            }
        }
    }

    func revertToMain() {
        if cancelPendingStemLoadAndRestoreMain() { return }
        guard mode == .aiStems else { return }
        DebugLogger.log("Reverting to main player", category: .playback)
        let wasPaused = _paused
        let shouldReleaseStemMedia = activeTemporaryStemLease != nil
        _paused = false
        if currentURL != nil {
            mainPlayer.volume = 1
            stopAllStems(releasingMedia: shouldReleaseStemMedia)
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
        stopAllStems(releasingMedia: shouldReleaseStemMedia)
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
            activeTemporaryStemLease?.cleanup()
            activeTemporaryStemLease = nil
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
        // Pausing changes playback intent, not load ownership. In-flight media
        // loads finish and consult their shouldPlay closure before starting.
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
        let wasPaused = _paused
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
            if wasPaused { pause() }
            return true
        }
        let dur = mainPlayer.duration
        guard dur.isFinite, dur > 0 else { return true }
        let upper = dur - 0.5
        guard upper > 0 else { return true }
        let target = max(0, min(seconds, upper))
        suppressionToken &+= 1
        safePlay(mainPlayer, from: target)
        if wasPaused { pause() }
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

        cancelCrossfadeRamp()
        cancelHandoffBlend()
        crossfadeFinalizeTask?.cancel()
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
                self.crossfadeDuration = duration.isFinite ? max(0, duration) : 0
                self.crossfadeElapsed = 0
                self.crossfadeStartTime = .now
                self.crossfadeRamp = ramp
                self.isCrossfading = true
                self.crossfadeStartMainVol = self.mainPlayer.volume
                self.crossfadeStartVocalsVol = self.stemVocals.volume
                self.crossfadeStartInstrumentalVol = self.stemInstrumental.volume
                self.crossfadePlayer.volume = 0
                self.startEngineIfNeeded()
                self.crossfadePlayer.play()
                self.onCrossfadeStarted?()
                DebugLogger.log(
                    "Crossfade playback started for \(url.lastPathComponent), handoffSource=\(Self.describeMedia(self.preparedCrossfadeMedia))",
                    category: .playback
                )
                let interval = Self.transitionTimerInterval
                let rampGeneration = self.crossfadeRampCompletionGate.begin()
                if self.crossfadeDuration <= interval {
                    self.applyCrossfadeProgress(1)
                    self.completeCrossfadeRamp(rampGeneration)
                    return
                }
                let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
                    guard self != nil else { timer.invalidate(); return }
                    let finished = MainActor.assumeIsolated { () -> Bool in
                        guard let self else { return true }
                        guard self.crossfadeRampCompletionGate.owns(rampGeneration) else {
                            return true
                        }
                        let elapsed = self.crossfadeStartTime.map { Date.now.timeIntervalSince($0) } ?? 0
                        self.crossfadeElapsed = elapsed
                        let t = Float(min(1.0, elapsed / self.crossfadeDuration))
                        self.applyCrossfadeProgress(t)
                        return t >= 1.0
                            ? self.completeCrossfadeRamp(rampGeneration)
                            : false
                    }
                    if finished { timer.invalidate() }
                }
                self.crossfadeTimer = timer
                RunLoop.main.add(timer, forMode: .common)
                let fallbackDelay = self.crossfadeDuration + interval
                self.crossfadeRampFallbackTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(fallbackDelay))
                    } catch {
                        return
                    }
                    self?.completeCrossfadeRamp(rampGeneration)
                }
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

    private func applyCrossfadeProgress(_ progress: Float) {
        let t = min(1, max(0, progress))
        let outVolume: Float
        let inVolume: Float
        switch crossfadeRamp {
        case .equalPower:
            outVolume = cos(t * .pi / 2)
            inVolume = sin(t * .pi / 2)
        case .linear:
            outVolume = 1 - t
            inVolume = t
        }
        if mode == .aiStems {
            mainPlayer.volume = max(0, crossfadeStartMainVol * outVolume)
            stemVocals.volume = max(0, crossfadeStartVocalsVol * outVolume)
            stemInstrumental.volume = max(0, crossfadeStartInstrumentalVol * outVolume)
        } else {
            mainPlayer.volume = max(0, outVolume)
        }
        crossfadePlayer.volume = max(0, inVolume)
    }

    @discardableResult
    private func completeCrossfadeRamp(_ generation: UInt64) -> Bool {
        guard crossfadeRampCompletionGate.consume(generation) else { return false }
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeRampFallbackTask?.cancel()
        crossfadeRampFallbackTask = nil
        applyCrossfadeProgress(1)
        finalizeCrossfade()
        return true
    }

    func cancelCrossfade() {
        cancelCrossfadeLoadTasks()
        cancelCrossfadeRamp()
        cancelHandoffBlend()
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
        cancelCrossfadeRamp()
        cancelHandoffBlend()
        isCrossfading = false

        suppressionToken &+= 1
        let token = suppressionToken
        let preparedMedia = preparedCrossfadeMedia
        DebugLogger.log(
            "Finalizing crossfade pending=\(pendingCrossfadeURL?.lastPathComponent ?? "nil"), prepared=\(Self.describeMedia(preparedMedia)), resumeTime=\(crossfadePlayer.currentTime)",
            category: .playback
        )
        cancelCrossfadeLoadTasks()
        releasePlayerMedia(mainPlayer, resetVolumeTo: 1)
        if mode == .aiStems {
            stopAllStems(releasingMedia: true)
        }

        crossfadePlayer.volume = 1.0

        if let url = pendingCrossfadeURL {
            let resumeTime = crossfadePlayer.currentTime
            do {
                if let preparedMedia {
                    let handoffMedia = try Self.handoffMedia(from: preparedMedia, sourceURL: url)
                    try completeCrossfadeHandoff(media: handoffMedia, url: url, resumeTime: resumeTime)
                } else {
                    DebugLogger.log(
                        "Crossfade handoff requires reload for \(url.lastPathComponent)",
                        category: .playback
                    )
                    crossfadeLoadGeneration &+= 1
                    let loadGeneration = crossfadeLoadGeneration
                    let loadTask = Task.detached(priority: .utility) {
                        LoadedMediaTransfer(value: try Self.loadMedia(url: url, intent: .immediatePlayback))
                    }
                    crossfadeFinalizeTask = loadTask
                    Task {
                        do {
                            let media = try await loadTask.value.value
                            guard self.suppressionToken == token,
                                  self.crossfadeLoadGeneration == loadGeneration
                            else { return }
                            DebugLogger.log(
                                "Crossfade reload complete for \(url.lastPathComponent): \(Self.describeMedia(media))",
                                category: .playback
                            )
                            try self.completeCrossfadeHandoff(media: media, url: url, resumeTime: resumeTime)
                        } catch is CancellationError {
                            guard self.crossfadeLoadGeneration == loadGeneration else { return }
                            self.crossfadeFinalizeTask = nil
                            self.pendingCrossfadeURL = nil
                            DebugLogger.log(
                                "Crossfade reload cancelled for \(url.lastPathComponent)", category: .playback
                            )
                        } catch {
                            guard self.suppressionToken == token,
                                  self.crossfadeLoadGeneration == loadGeneration
                            else { return }
                            self.crossfadeFinalizeTask = nil
                            self.pendingCrossfadeURL = nil
                            self.releasePlayerMedia(self.crossfadePlayer)
                            DebugLogger.log(
                                "Crossfade reload failed for \(url.lastPathComponent): \(error)",
                                category: .playback
                            )
                            self.onPlaybackError?(error)
                        }
                    }
                    return
                }
            } catch {
                pendingCrossfadeURL = nil
                releasePlayerMedia(crossfadePlayer)
                onPlaybackError?(error)
            }
        } else {
            releasePlayerMedia(crossfadePlayer)
            pendingCrossfadeURL = nil
            onCrossfadeCompleted?()
        }
    }

    private func clearPendingStemLoadContext(
        for token: StemLoadOwnershipGate.Token,
        notifyCancellation: Bool = false,
        cleanupTemporaryLease: Bool = false
    ) {
        guard let context = pendingStemLoadContext, context.token == token else { return }
        pendingStemLoadContext = nil
        if cleanupTemporaryLease {
            context.temporaryLease?.cleanup()
        }
        if notifyCancellation {
            context.onCancelled()
        }
    }

    @discardableResult
    private func cancelPendingStemLoadAndRestoreMain() -> Bool {
        guard let context = pendingStemLoadContext,
              stemLoadOwnership.owns(context.token)
        else { return false }

        DebugLogger.log("Cancelling pending AI stem load", category: .playback)
        let recovery = context.token.recovery
        let originalURL = context.originalURL
        let startAt = context.startAt
        let shouldPlay = context.shouldPlay

        suppressionToken &+= 1
        cancelPrimaryLoadTasks()
        stopAllStems(releasingMedia: true)
        mode = .single
        aiStartOffset = 0
        resetInstrumentalEQ()

        guard recovery == .reloadOriginal, let originalURL else { return true }
        play(url: originalURL, startAt: startAt, shouldPlay: shouldPlay)
        return true
    }

    private func cancelPrimaryLoadTasks() {
        let cancelledStemContext = pendingStemLoadContext
        primaryLoadGeneration &+= 1
        singleLoadTask?.cancel()
        stemsLoadTask?.cancel()
        switchToStemsLoadTask?.cancel()
        stemLoadOwnership.cancel()
        singleLoadTask = nil
        stemsLoadTask = nil
        switchToStemsLoadTask = nil
        pendingStemLoadContext = nil
        cancelledStemContext?.temporaryLease?.cleanup()
        cancelledStemContext?.onCancelled()
    }

    private func cancelCrossfadeLoadTasks() {
        crossfadeLoadGeneration &+= 1
        crossfadePreloadTask?.cancel()
        crossfadeFinalizeTask?.cancel()
        crossfadePreloadTask = nil
        crossfadeFinalizeTask = nil
        crossfadePreloadURL = nil
        preparedCrossfadeMedia = nil
    }

    private func releasePlayerMedia(_ player: SimpleAudioPlayer, resetVolumeTo volume: Float = 0) {
        player.stop()
        player.playerNode.reset()
        player.volume = volume
        if let buffer = Self.silenceBuffer {
            player.load(buffer: buffer)
        }
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

    private func completeCrossfadeHandoff(
        media: LoadedMedia?,
        url: URL,
        resumeTime: TimeInterval
    ) throws {
        guard Self.containsPlayableMedia(media) else {
            throw NSError(
                domain: "AVEnginePlayback",
                code: -1001,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Crossfade handoff for \(url.lastPathComponent) finished without playable media",
                ]
            )
        }
        if let media {
            try applyMedia(media, to: mainPlayer)
        }
        crossfadeFinalizeTask = nil
        preparedCrossfadeMedia = nil
        mode = .single
        aiStartOffset = 0
        stopAllStems(releasingMedia: true)
        mainPlayer.volume = 0
        resetInstrumentalEQ()
        startEngineIfNeeded()
        let loadedDuration = mainPlayer.duration
        guard loadedDuration.isFinite, loadedDuration > 0.1 else {
            throw NSError(
                domain: "AVEnginePlayback",
                code: -1002,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Crossfade handoff for \(url.lastPathComponent) loaded invalid duration \(loadedDuration)",
                ]
            )
        }
        let handoffLeadTime: TimeInterval = 0.08
        let handoffStartTime = synchronizedStartTime(leadTime: handoffLeadTime)
        let freshTime = crossfadePlayer.currentTime
        let actualResume = crossfadePlayer.isPlaying && freshTime > resumeTime
            ? freshTime : resumeTime
        let scheduledResume = actualResume + handoffLeadTime
        safePlay(mainPlayer, from: scheduledResume, at: handoffStartTime)
        currentURL = url
        DebugLogger.log(
            "Crossfade handoff complete url=\(url.lastPathComponent), media=\(Self.describeMedia(media)), resumeTime=\(scheduledResume), mainTime=\(mainPlayer.currentTime), mainDuration=\(mainPlayer.duration)",
            category: .playback
        )
        beginCrossfadeHandoffBlend(after: handoffLeadTime) { [weak self] in
            self?.onCrossfadeCompleted?()
        }
        pendingCrossfadeURL = nil
    }

    private func beginCrossfadeHandoffBlend(after delay: TimeInterval, completion: @escaping @MainActor @Sendable () -> Void) {
        cancelHandoffBlend()
        let generation = handoffBlendCompletionGate.begin()
        let safeDelay = delay.isFinite ? max(0, delay) : 0
        let duration: TimeInterval = 0.35
        let interval = Self.transitionTimerInterval
        let startTime = Date.now
        if safeDelay + duration <= interval {
            finishCrossfadeHandoffBlend(generation, completion: completion)
            return
        }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            // The timer itself must not be touched inside the isolated closure,
            // so it reports completion and invalidation happens out here.
            let finished = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return true }
                guard self.handoffBlendCompletionGate.owns(generation) else {
                    return true
                }
                let elapsed = Date.now.timeIntervalSince(startTime) - safeDelay
                guard elapsed >= 0 else {
                    self.mainPlayer.volume = 0
                    self.crossfadePlayer.volume = 1.0
                    return false
                }
                let t = Float(min(1.0, max(0.0, elapsed / duration)))
                self.mainPlayer.volume = t
                self.crossfadePlayer.volume = 1.0 - t
                if t >= 1.0 {
                    return self.finishCrossfadeHandoffBlend(
                        generation,
                        completion: completion
                    )
                }
                return false
            }
            if finished { timer.invalidate() }
        }
        handoffBlendTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        let fallbackDelay = safeDelay + duration + interval
        handoffBlendFallbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(fallbackDelay))
            } catch {
                return
            }
            self?.finishCrossfadeHandoffBlend(generation, completion: completion)
        }
    }

    @discardableResult
    private func finishCrossfadeHandoffBlend(
        _ generation: UInt64,
        completion: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        guard handoffBlendCompletionGate.consume(generation) else { return false }
        handoffBlendTimer?.invalidate()
        handoffBlendTimer = nil
        handoffBlendFallbackTask?.cancel()
        handoffBlendFallbackTask = nil
        mainPlayer.volume = 1
        releasePlayerMedia(crossfadePlayer)
        completion()
        return true
    }

    private static func handoffMedia(
        from preparedMedia: LoadedMedia,
        sourceURL: URL
    ) throws -> LoadedMedia {
        if let preparedBuffer = preparedMedia.1 {
            if let clonedBuffer = cloneBuffer(preparedBuffer) {
                DebugLogger.log(
                    "Crossfade handoff cloning prepared buffer for \(sourceURL.lastPathComponent)",
                    category: .playback
                )
                return (nil, clonedBuffer)
            }
            DebugLogger.log(
                "Crossfade handoff reloading unclonable buffer for \(sourceURL.lastPathComponent)",
                category: .playback
            )
            return try loadMedia(url: sourceURL, intent: .immediatePlayback)
        }
        DebugLogger.log(
            "Crossfade handoff reloading file-backed media for \(sourceURL.lastPathComponent)",
            category: .playback
        )
        return try loadMedia(url: sourceURL, intent: .immediatePlayback)
    }

    private static func cloneBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard
            buffer.format.commonFormat == .pcmFormatFloat32,
            !buffer.format.isInterleaved,
            let sourceChannels = buffer.floatChannelData,
            let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity),
            let destinationChannels = copy.floatChannelData
        else { return nil }
        copy.frameLength = buffer.frameLength
        let channelCount = Int(buffer.format.channelCount)
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
        for channel in 0 ..< channelCount {
            memcpy(destinationChannels[channel], sourceChannels[channel], byteCount)
        }
        return copy
    }

    private static func describeMedia(_ media: LoadedMedia?) -> String {
        guard let media else { return "none" }
        if media.0 != nil { return "file" }
        if let buffer = media.1 {
            return "buffer(\(buffer.frameLength)f)"
        }
        return "empty"
    }

    private static func containsPlayableMedia(_ media: LoadedMedia?) -> Bool {
        guard let media else { return false }
        if media.0 != nil { return true }
        if let buffer = media.1 {
            return buffer.frameLength > 0
        }
        return false
    }

    private static let silenceBuffer: AVAudioPCMBuffer? = {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44100,
                channels: 2,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)
        else { return nil }
        buffer.frameLength = 1024
        for channel in 0 ..< Int(format.channelCount) {
            buffer.floatChannelData?[channel].update(repeating: 0, count: Int(buffer.frameLength))
        }
        return buffer
    }()
}
