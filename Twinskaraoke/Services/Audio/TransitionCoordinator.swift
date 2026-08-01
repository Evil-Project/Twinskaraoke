import Foundation

@MainActor
final class TransitionCoordinator {
    private struct BPMCacheEntry: Codable {
        let bpm: Double
        let updatedAt: TimeInterval
    }

    enum State {
        case idle
        case preparing(nextSong: Song, queueIndex: Int)
        case ready(plan: TransitionPlan)
        case crossfading(plan: TransitionPlan)

        var isCrossfading: Bool {
            if case .crossfading = self { return true }
            return false
        }

        var isPreparing: Bool {
            if case .preparing = self { return true }
            return false
        }
    }

    struct TransitionPlan {
        let nextSong: Song
        let nextQueueIndex: Int
        let nextFileURL: URL
        let outgoingBPM: Double?
        let incomingBPM: Double?
        let fadeDuration: TimeInterval
        let rampStyle: AVEnginePlayback.RampStyle
    }

    private(set) var state: State = .idle
    private var bpmTask: Task<Void, Never>?
    private var predownloadSession: PredownloadSession?

    weak var avEngine: AVEnginePlayback?

    var onBeginTransition: ((TransitionPlan) -> Void)?

    var onUpcomingSongDetermined: ((Song?) -> Void)?

    private let prepareLeadTime: TimeInterval = 30

    private let prepareLeadFraction: Double = 0.5

    private static let bpmCacheKey = "nk.bpmCache.v2"
    private static let legacyBPMCacheKey = "nk.bpmCache"
    private static let bpmCacheTTL: TimeInterval = 3600
    private static let bpmCacheLimit = 500

    private var bpmCache: [String: BPMCacheEntry] = TransitionCoordinator.loadBPMCache()

    func cachedBPM(for songID: String) -> Double? {
        guard let entry = validBPMEntry(for: songID) else { return nil }
        return entry.bpm
    }

    private func storeBPM(_ bpm: Double, for songID: String) {
        pruneExpiredBPMCache()
        bpmCache[songID] = BPMCacheEntry(bpm: bpm, updatedAt: Date().timeIntervalSince1970)
        if bpmCache.count > Self.bpmCacheLimit {
            let overflow = bpmCache.count - Self.bpmCacheLimit
            let keysToRemove = bpmCache
                .sorted { $0.value.updatedAt < $1.value.updatedAt }
                .prefix(overflow)
                .map(\.key)
            for key in keysToRemove {
                bpmCache.removeValue(forKey: key)
            }
        }
        persistBPMCache()
    }

    func poll(
        currentTime: TimeInterval,
        totalDuration: TimeInterval,
        currentSong: Song?,
        currentQueueIndex: Int?,
        queue: [Song],
        repeatMode: RepeatMode,
        autoMixEnabled: Bool,
        crossfadeEnabled: Bool,
        crossfadeSeconds: Double,
        aiEffectActive: Bool
    ) {
        guard totalDuration > 0, let currentSong else { return }
        guard autoMixEnabled || crossfadeEnabled else {
            if case .idle = state {} else { reset() }
            return
        }

        let remaining = totalDuration - currentTime
        let prepareAt = min(prepareLeadTime, totalDuration * prepareLeadFraction)
        let nextSelection = QueueOccurrenceNavigator.nextSelection(
            currentSong: currentSong,
            currentIndex: currentQueueIndex,
            queue: queue,
            wrapsAtEnd: repeatMode == .all
        )

        switch state {
        case .idle:
            guard remaining <= prepareAt, remaining > 0 else { return }
            if let nextSelection {
                beginPreparing(
                    nextSong: nextSelection.song,
                    nextQueueIndex: nextSelection.index,
                    currentSong: currentSong,
                    autoMixEnabled: autoMixEnabled, crossfadeSeconds: crossfadeSeconds,
                    aiEffectActive: aiEffectActive
                )
            }

        case let .preparing(nextSong, queueIndex):
            guard let nextSelection,
                  nextSelection.index == queueIndex,
                  QueueOccurrenceNavigator.exactlyMatches(nextSelection.song, nextSong)
            else {
                reset()
                return
            }

        case let .ready(plan):
            guard let nextSelection,
                  nextSelection.index == plan.nextQueueIndex,
                  QueueOccurrenceNavigator.exactlyMatches(nextSelection.song, plan.nextSong)
            else {
                reset()
                return
            }
            if remaining <= plan.fadeDuration + 0.1 {
                DebugLogger.log(
                    "Transition ready -> crossfading for next=\(plan.nextSong.id), remaining=\(remaining), fade=\(plan.fadeDuration), ramp=\(plan.rampStyle)",
                    category: .playback
                )
                state = .crossfading(plan: plan)
                onBeginTransition?(plan)
            }

        case .crossfading:
            break
        }
    }

    private func beginPreparing(
        nextSong: Song,
        nextQueueIndex: Int,
        currentSong: Song,
        autoMixEnabled: Bool, crossfadeSeconds: Double,
        aiEffectActive: Bool
    ) {
        DebugLogger.log(
            "Preparing transition current=\(currentSong.id) next=\(nextSong.id), autoMix=\(autoMixEnabled), crossfadeSeconds=\(crossfadeSeconds), aiEffectActive=\(aiEffectActive)",
            category: .playback
        )
        state = .preparing(nextSong: nextSong, queueIndex: nextQueueIndex)
        onUpcomingSongDetermined?(nextSong)

        bpmTask?.cancel()
        predownloadSession?.cancel()
        predownloadSession = nil
        bpmTask = Task { [weak self] in
            guard let self else { return }

            let currentURL = audioFileURL(for: currentSong)
            let nextURL = audioFileURL(for: nextSong)

            if nextURL == nil, let remoteURL = nextSong.audioURL {
                DebugLogger.log(
                    "Predownloading next transition track \(nextSong.id) from \(remoteURL.lastPathComponent)",
                    category: .playback
                )
                await predownload(song: nextSong, from: remoteURL)
            }

            let nextFileURL = audioFileURL(for: nextSong)
            let shouldAnalyzeBPM = autoMixEnabled && !aiEffectActive
            let outBPM: Double?
            let inBPM: Double?
            if shouldAnalyzeBPM {
                async let outBPMResult = detectBPM(for: currentSong, fileURL: currentURL)
                async let inBPMResult = detectBPM(for: nextSong, fileURL: nextFileURL)
                outBPM = await outBPMResult
                inBPM = await inBPMResult
            } else {
                outBPM = nil
                inBPM = nil
            }

            if Task.isCancelled { return }

            let fadeDuration: TimeInterval
            let rampStyle: AVEnginePlayback.RampStyle

            if autoMixEnabled {
                if aiEffectActive {
                    fadeDuration = 1.2
                    rampStyle = .linear
                } else {
                    let result = Self.computeFade(outBPM: outBPM, inBPM: inBPM)

                    fadeDuration = min(result.duration, max(1.0, crossfadeSeconds))
                    rampStyle = result.style
                }
            } else {
                fadeDuration = crossfadeSeconds
                rampStyle = .equalPower
            }

            guard let fileURL = audioFileURL(for: nextSong) else {
                await MainActor.run { [weak self] in self?.reset() }
                return
            }

            let plan = TransitionPlan(
                nextSong: nextSong,
                nextQueueIndex: nextQueueIndex,
                nextFileURL: fileURL,
                outgoingBPM: outBPM,
                incomingBPM: inBPM,
                fadeDuration: fadeDuration,
                rampStyle: rampStyle
            )
            let outBPMText = outBPM.map { String(format: "%.2f", $0) } ?? "nil"
            let inBPMText = inBPM.map { String(format: "%.2f", $0) } ?? "nil"

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard case let .preparing(song, queueIndex) = state,
                      queueIndex == nextQueueIndex,
                      QueueOccurrenceNavigator.exactlyMatches(song, nextSong)
                else { return }
                DebugLogger.log(
                    "Transition prepared next=\(nextSong.id), file=\(fileURL.lastPathComponent), outBPM=\(outBPMText), inBPM=\(inBPMText), fade=\(fadeDuration), ramp=\(rampStyle)",
                    category: .playback
                )
                state = .ready(plan: plan)
                if !aiEffectActive {
                    avEngine?.preloadCrossfade(url: fileURL)
                }
            }
        }
    }

    private func detectBPM(for song: Song, fileURL: URL?) async -> Double? {
        if let cached = cachedBPM(for: song.id) { return cached }
        guard let url = fileURL else { return nil }
        guard let bpm = await BPMDetector.detect(url: url) else { return nil }
        await MainActor.run { [weak self] in
            self?.storeBPM(bpm, for: song.id)
        }
        return bpm
    }

    static func computeFade(
        outBPM: Double?, inBPM: Double?
    ) -> (duration: TimeInterval, style: AVEnginePlayback.RampStyle) {
        guard let out = outBPM, out.isFinite, out > 0,
              let inB = inBPM, inB.isFinite, inB > 0
        else {
            return (6.0, .equalPower)
        }
        let diff = harmonicBPMDifference(out, inB)
        if diff <= 8 {
            let beatDur = 60.0 / out
            let targetBeats = max(4, (8.0 / beatDur).rounded())
            return (targetBeats * beatDur, .equalPower)
        } else if diff <= 20 {
            return (4.0, .equalPower)
        } else {
            return (1.5, .linear)
        }
    }

    static func harmonicBPMDifference(_ a: Double, _ b: Double) -> Double {
        [b, b * 2, b / 2].map { abs(a - $0) }.min()!
    }

    private func audioFileURL(for song: Song) -> URL? {
        if let downloaded = DownloadManager.shared.playableURL(for: song) {
            return downloaded
        }
        let expectedDuration = song.duration > 0 ? TimeInterval(song.duration) : nil
        return AudioCacheStore.playableMainURL(for: song.id, expectedRemoteURL: song.audioURL, expectedDuration: expectedDuration)
    }

    private func predownload(song: Song, from remoteURL: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let sessionID = UUID()
            let session = PredownloadSession(
                id: sessionID,
                songID: song.id,
                expectedDuration: song.duration > 0 ? TimeInterval(song.duration) : nil,
                onCompletion: { [weak self] in
                    DebugLogger.log(
                        "Predownload finished for next transition track \(song.id)",
                        category: .playback
                    )
                    if self?.predownloadSession?.id == sessionID {
                        self?.predownloadSession = nil
                    }
                    continuation.resume()
                }
            )
            self.predownloadSession = session
            session.start(from: remoteURL)
            if Task.isCancelled {
                session.cancel()
            }
        }
    }

    func reset() {
        DebugLogger.log("Transition coordinator reset from \(stateDescription(state))", category: .playback)
        bpmTask?.cancel()
        bpmTask = nil
        predownloadSession?.cancel()
        predownloadSession = nil
        state = .idle
        onUpcomingSongDetermined?(nil)
    }

    private func stateDescription(_ state: State) -> String {
        switch state {
        case .idle:
            "idle"
        case let .preparing(song, queueIndex):
            "preparing(\(song.id)@\(queueIndex))"
        case let .ready(plan):
            "ready(\(plan.nextSong.id), fade=\(plan.fadeDuration))"
        case let .crossfading(plan):
            "crossfading(\(plan.nextSong.id), fade=\(plan.fadeDuration))"
        }
    }

    private static func loadBPMCache() -> [String: BPMCacheEntry] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: bpmCacheKey),
           let decoded = try? JSONDecoder().decode([String: BPMCacheEntry].self, from: data)
        {
            return decoded
        }
        if let legacy = defaults.dictionary(forKey: legacyBPMCacheKey) as? [String: Double] {
            let now = Date().timeIntervalSince1970
            return legacy.reduce(into: [String: BPMCacheEntry]()) { result, item in
                result[item.key] = BPMCacheEntry(bpm: item.value, updatedAt: now)
            }
        }
        return [:]
    }

    private func validBPMEntry(for songID: String) -> BPMCacheEntry? {
        guard let entry = bpmCache[songID] else { return nil }
        let now = Date().timeIntervalSince1970
        guard now - entry.updatedAt < Self.bpmCacheTTL else {
            bpmCache.removeValue(forKey: songID)
            persistBPMCache()
            return nil
        }
        return entry
    }

    private func pruneExpiredBPMCache() {
        let now = Date().timeIntervalSince1970
        let before = bpmCache.count
        bpmCache = bpmCache.filter { now - $0.value.updatedAt < Self.bpmCacheTTL }
        if bpmCache.count != before {
            persistBPMCache()
        }
    }

    private func persistBPMCache() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(bpmCache) {
            defaults.set(data, forKey: Self.bpmCacheKey)
        } else {
            defaults.removeObject(forKey: Self.bpmCacheKey)
        }
    }
}

// URLSession delegates must be Sendable; cross-thread state is guarded by stateLock.
private final class PredownloadSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let id: UUID
    private let songID: String
    private let expectedDuration: TimeInterval?
    private var lease: AudioCacheStore.MainWriteLease?
    private var fileHandle: FileHandle?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private let stateLock = NSLock()
    private var lifecycle = PredownloadLifecycleState()
    private let completionGate: PredownloadCompletionGate

    init(
        id: UUID,
        songID: String,
        expectedDuration: TimeInterval?,
        onCompletion: @escaping PredownloadCompletionGate.Completion
    ) {
        self.id = id
        self.songID = songID
        self.expectedDuration = expectedDuration
        completionGate = PredownloadCompletionGate(completion: onCompletion)
        super.init()
    }

    func start(from remoteURL: URL) {
        if AudioCacheStore.playableMainURL(for: songID, expectedRemoteURL: remoteURL, expectedDuration: expectedDuration) != nil {
            DebugLogger.log("Predownload cache hit for \(songID)", category: .playback)
            stateLock.lock()
            let didFinish = lifecycle.finishWithoutValidation()
            stateLock.unlock()
            if didFinish { finish() }
            return
        }
        DebugLogger.log("Predownload start for \(songID) from \(remoteURL.lastPathComponent)", category: .playback)
        let createdLease = AudioCacheStore.beginMainWrite(songID: songID, sourceURL: remoteURL)
        let stagingURL = createdLease.mainStagingURL
        try? FileManager.default.removeItem(at: stagingURL)
        FileManager.default.createFile(atPath: stagingURL.path, contents: nil)
        guard let createdFileHandle = try? FileHandle(forWritingTo: stagingURL) else {
            AudioCacheStore.cancelMainWrite(createdLease)
            stateLock.lock()
            let didFinish = lifecycle.finishWithoutValidation()
            stateLock.unlock()
            if didFinish { finish() }
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let createdSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let createdTask = createdSession.dataTask(with: remoteURL)

        stateLock.lock()
        guard lifecycle.phase == .running else {
            stateLock.unlock()
            try? createdFileHandle.close()
            createdSession.invalidateAndCancel()
            AudioCacheStore.cancelMainWrite(createdLease)
            finish()
            return
        }
        lease = createdLease
        fileHandle = createdFileHandle
        session = createdSession
        task = createdTask
        stateLock.unlock()
        createdTask.resume()
    }

    func cancel() {
        DebugLogger.log("Predownload cancelled for \(songID)", category: .playback)
        stateLock.lock()
        let didCancel = lifecycle.cancel()
        let activeTask = task
        let activeSession = session
        let activeFileHandle = fileHandle
        let activeLease = lease
        fileHandle = nil
        task = nil
        session = nil
        lease = nil
        stateLock.unlock()
        guard didCancel else { return }

        activeTask?.cancel()
        activeSession?.invalidateAndCancel()
        try? activeFileHandle?.close()
        if let activeLease {
            AudioCacheStore.cancelMainWrite(activeLease)
        }
        finish()
    }

    func urlSession(
        _: URLSession, dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard AudioCacheStore.acceptsAudioResponse(response) else {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        stateLock.lock()
        if lifecycle.phase == .running {
            fileHandle?.write(data)
        }
        stateLock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateLock.lock()
        guard lifecycle.beginValidation() else {
            stateLock.unlock()
            session.invalidateAndCancel()
            return
        }
        let completedFileHandle = fileHandle
        let completedLease = lease
        fileHandle = nil
        self.task = nil
        self.session = nil
        stateLock.unlock()

        try? completedFileHandle?.close()
        session.invalidateAndCancel()

        let isValidDownload = error == nil
            && AudioCacheStore.acceptsAudioResponse(task.response)
            && completedLease.map { AudioCacheStore.isPlayableAudioFile(at: $0.mainStagingURL) } == true

        stateLock.lock()
        guard lifecycle.finishValidation() else {
            stateLock.unlock()
            if let completedLease {
                AudioCacheStore.cancelMainWrite(completedLease)
            }
            return
        }
        lease = nil
        stateLock.unlock()

        if isValidDownload, let completedLease {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            DebugLogger.log("Predownload completed for \(songID) with HTTP \(status)", category: .playback)
            do {
                if try AudioCacheStore.commitMainWrite(completedLease) == false {
                    DebugLogger.log("Predownload commit superseded for \(songID)", category: .playback)
                }
            } catch {
                DebugLogger.log("Predownload commit failed for \(songID): \(error)", category: .playback)
                AudioCacheStore.cancelMainWrite(completedLease)
            }
        } else {
            DebugLogger.log(
                "Predownload failed for \(songID): \(error?.localizedDescription ?? "bad response")",
                category: .playback
            )
            if let completedLease {
                AudioCacheStore.cancelMainWrite(completedLease)
            }
        }
        finish()
    }

    private func finish() {
        guard let completion = completionGate.take() else { return }
        Task { @MainActor in
            completion()
        }
    }
}
