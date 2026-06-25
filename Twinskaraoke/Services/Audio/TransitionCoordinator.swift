import Foundation

@MainActor
final class TransitionCoordinator {
    private struct BPMCacheEntry: Codable {
        let bpm: Double
        let updatedAt: TimeInterval
    }

    enum State {
        case idle
        case preparing(nextSong: Song)
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

        switch state {
        case .idle:
            guard remaining <= prepareAt, remaining > 0 else { return }
            if let nextSong = nextSongInQueue(current: currentSong, queue: queue, repeatMode: repeatMode) {
                beginPreparing(
                    nextSong: nextSong, currentSong: currentSong,
                    autoMixEnabled: autoMixEnabled, crossfadeSeconds: crossfadeSeconds,
                    aiEffectActive: aiEffectActive
                )
            }

        case .preparing:
            break

        case let .ready(plan):
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
        nextSong: Song, currentSong: Song,
        autoMixEnabled: Bool, crossfadeSeconds: Double,
        aiEffectActive: Bool
    ) {
        DebugLogger.log(
            "Preparing transition current=\(currentSong.id) next=\(nextSong.id), autoMix=\(autoMixEnabled), crossfadeSeconds=\(crossfadeSeconds), aiEffectActive=\(aiEffectActive)",
            category: .playback
        )
        state = .preparing(nextSong: nextSong)
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
                guard case let .preparing(s) = state, s.id == nextSong.id else { return }
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
        guard let out = outBPM, let inB = inBPM else {
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

    private func nextSongInQueue(current: Song, queue: [Song], repeatMode: RepeatMode) -> Song? {
        guard !queue.isEmpty, let idx = queue.firstIndex(where: { $0.id == current.id }) else { return nil }
        if idx + 1 < queue.count { return queue[idx + 1] }
        if repeatMode == .all { return queue.first }
        return nil
    }

    private func predownload(song: Song, from remoteURL: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let session = PredownloadSession(songID: song.id, expectedDuration: song.duration > 0 ? TimeInterval(song.duration) : nil)
            self.predownloadSession = session
            session.onCompletion = { [weak self] in
                DebugLogger.log(
                    "Predownload finished for next transition track \(song.id)",
                    category: .playback
                )
                self?.predownloadSession = nil
                continuation.resume()
            }
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
        case let .preparing(song):
            "preparing(\(song.id))"
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

private final class PredownloadSession: NSObject, URLSessionDataDelegate {
    private let songID: String
    private let expectedDuration: TimeInterval?
    private let partialURL: URL
    private let finalURL: URL
    private var remoteURL: URL?
    private var fileHandle: FileHandle?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var didComplete = false
    private let stateLock = NSLock()
    private var isCancelled = false
    var onCompletion: (() -> Void)?

    init(songID: String, expectedDuration: TimeInterval?) {
        self.songID = songID
        self.expectedDuration = expectedDuration
        let songFiles = AudioCacheStore.files(for: songID)
        finalURL = songFiles.main
        partialURL = songFiles.mainPartial
        super.init()
    }

    func start(from remoteURL: URL) {
        self.remoteURL = remoteURL
        if AudioCacheStore.playableMainURL(for: songID, expectedRemoteURL: remoteURL, expectedDuration: expectedDuration) != nil {
            DebugLogger.log("Predownload cache hit for \(songID)", category: .playback)
            finish()
            return
        }
        DebugLogger.log("Predownload start for \(songID) from \(remoteURL.lastPathComponent)", category: .playback)
        try? FileManager.default.removeItem(at: partialURL)
        FileManager.default.createFile(atPath: partialURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: partialURL)
        guard fileHandle != nil else {
            try? FileManager.default.removeItem(at: partialURL)
            finish()
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        task = session?.dataTask(with: remoteURL)
        task?.resume()
    }

    func cancel() {
        DebugLogger.log("Predownload cancelled for \(songID)", category: .playback)
        stateLock.lock()
        isCancelled = true
        task?.cancel()
        session?.invalidateAndCancel()
        fileHandle?.closeFile()
        fileHandle = nil
        task = nil
        session = nil
        stateLock.unlock()
        try? FileManager.default.removeItem(at: partialURL)
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
        let cancelled = isCancelled
        if !cancelled {
            fileHandle?.write(data)
        }
        stateLock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateLock.lock()
        let cancelled = isCancelled
        fileHandle?.closeFile()
        fileHandle = nil
        stateLock.unlock()
        session.invalidateAndCancel()
        self.task = nil
        self.session = nil
        guard !cancelled else { return }
        if error == nil, AudioCacheStore.acceptsAudioResponse(task.response),
           AudioCacheStore.isPlayableAudioFile(at: partialURL)
        {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            DebugLogger.log("Predownload completed for \(songID) with HTTP \(status)", category: .playback)
            do {
                try? FileManager.default.removeItem(at: finalURL)
                try FileManager.default.moveItem(at: partialURL, to: finalURL)
                AudioCacheStore.writeMainSourceURL(remoteURL, for: songID)
            } catch {
                DebugLogger.log("Predownload move failed for \(songID): \(error)", category: .playback)
                try? FileManager.default.removeItem(at: partialURL)
                AudioCacheStore.writeMainSourceURL(nil, for: songID)
            }
        } else {
            DebugLogger.log(
                "Predownload failed for \(songID): \(error?.localizedDescription ?? "bad response")",
                category: .playback
            )
            try? FileManager.default.removeItem(at: partialURL)
        }
        finish()
    }

    private func finish() {
        guard !didComplete else { return }
        didComplete = true
        let completion = onCompletion
        onCompletion = nil
        if Thread.isMainThread {
            completion?()
        } else {
            DispatchQueue.main.async { completion?() }
        }
    }
}
