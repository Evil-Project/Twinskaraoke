import AVFoundation
import CoreMedia
import Foundation

/// Reader, renderer, synchronizer, and playback state are confined to queue.
/// The sample source contains an immutable asset and mix, and only this worker
/// advances its reader. Clock values and events cross back to the main actor.
nonisolated final class AirPlaySampleRenderer: @unchecked Sendable {
    enum Event: Sendable {
        case playing
        case failed
        case ended
    }

    private let queue = DispatchQueue(label: "Twinskaraoke.airplay.samples", qos: .userInitiated)
    private let renderer = AVSampleBufferAudioRenderer()
    private let clock = AVSampleBufferRenderSynchronizer()
    private let event: @Sendable (Int, Event) -> Void
    private let time: @Sendable (Int, Double) -> Void
    private var cursor: AirPlaySampleSource.Cursor?
    private var firstSpliceBuffer: CMSampleBuffer?
    private var nextEnqueueTime = CMTime.invalid
    private var source: AirPlaySampleSource?
    private var observation: Any?
    private var flushObserver: NSObjectProtocol?
    private var requested = false
    private var reachedEnd = false
    private var generation = 0
    private var retirementCallbacks: [@Sendable () -> Void]?
    private var didRetire = false

    #if DEBUG
        private var flushCount = 0
        private var spliceTime: Double?
    #endif

    init(event: @escaping @Sendable (Int, Event) -> Void, time: @escaping @Sendable (Int, Double) -> Void) {
        self.event = event
        self.time = time
        clock.addRenderer(renderer)
        observation = clock.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: queue
        ) { [weak self] position in
            self?.observe(position)
        }
        flushObserver = NotificationCenter.default.addObserver(
            forName: .AVSampleBufferAudioRendererWasFlushedAutomatically, object: renderer, queue: nil
        ) { [weak self] note in
            let position = (note.userInfo?[AVSampleBufferAudioRendererFlushTimeKey] as? NSValue)?.timeValue
            guard let self else { return }
            self.queue.async {
                guard let source = self.source else { return }
                let current = self.clock.currentTime()
                let resume = position.flatMap { $0.isNumeric ? min($0, current) : nil } ?? current
                self.replace(source, at: resume, autoplay: self.requested, generation: self.generation)
            }
        }
    }

    func load(_ source: AirPlaySampleSource, position: Double, autoplay: Bool, generation: Int) {
        queue.async {
            self.replace(source, at: CMTime(seconds: position, preferredTimescale: 48_000), autoplay: autoplay, generation: generation)
        }
    }

    func splice(_ source: AirPlaySampleSource, generation: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.spliceOnQueue(source, generation: generation))
            }
        }
    }

    private func spliceOnQueue(_ source: AirPlaySampleSource, generation: Int) -> Bool {
        guard self.generation == generation, cursor != nil, let timing = source.timing,
              nextEnqueueTime.isNumeric, nextEnqueueTime >= timing.outgoingStart,
              nextEnqueueTime.seconds <= timing.overlapStart else { return false }
        do {
            // Open and prime the replacement before touching the current reader.
            let replacement = try source.makeCursor(at: nextEnqueueTime)
            guard let first = try replacement.nextBuffer(),
                  first.outputPresentationTimeStamp == nextEnqueueTime,
                  nextEnqueueTime >= clock.currentTime() else {
                replacement.cancel()
                return false
            }
            cursor?.cancel()
            cursor = replacement
            firstSpliceBuffer = first
            self.source = source
            #if DEBUG
                spliceTime = first.outputPresentationTimeStamp.seconds
            #endif
            if reachedEnd {
                reachedEnd = false
                requestMediaData()
            }
            return true
        } catch {
            DebugLogger.log("AirPlay sample splice failed: \(error)", category: .playback)
            return false
        }
    }

    func setPlaying(_ playing: Bool) {
        queue.async {
            guard self.source != nil else { return }
            self.requested = playing
            self.clock.rate = playing ? 1 : 0
            if playing { self.event(self.generation, .playing) }
        }
    }

    func stop() {
        queue.async {
            self.stopReading()
            self.source = nil
        }
    }

    func retire(completion: (@Sendable () -> Void)?) {
        queue.async {
            if self.didRetire {
                completion?()
                return
            }
            if self.retirementCallbacks != nil {
                if let completion { self.retirementCallbacks?.append(completion) }
                return
            }
            self.retirementCallbacks = completion.map { [$0] } ?? []
            self.renderer.isMuted = true
            self.stopReading()
            self.source = nil
            // Flush drops queued samples locally. Wait for the synchronizer to
            // detach the renderer before handing playback to the local engine.
            self.clock.removeRenderer(self.renderer, at: .invalid) { _ in
                self.queue.async {
                    self.didRetire = true
                    let callbacks = self.retirementCallbacks
                    self.retirementCallbacks = nil
                    callbacks?.forEach { $0() }
                }
            }
        }
    }

    #if DEBUG
        func stateForTesting() async -> (position: Double, rate: Float, flushCount: Int, spliceTime: Double?) {
            await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: (self.clock.currentTime().seconds, self.clock.rate, self.flushCount, self.spliceTime))
                }
            }
        }

        func isMutedForTesting() async -> Bool {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: self.renderer.isMuted) }
            }
        }
    #endif

    private func replace(_ source: AirPlaySampleSource, at position: CMTime, autoplay: Bool, generation: Int) {
        stopReading()
        self.source = source
        requested = autoplay
        reachedEnd = false
        self.generation = generation
        clock.setRate(0, time: position)
        nextEnqueueTime = position
        do {
            cursor = try source.makeCursor(at: position)
            requestMediaData()
        } catch {
            fail()
        }
    }

    private func requestMediaData() {
        renderer.requestMediaDataWhenReady(on: queue) { [weak self] in self?.feed() }
    }

    private func stopReading() {
        requested = false
        clock.rate = 0
        renderer.stopRequestingMediaData()
        renderer.flush()
        #if DEBUG
            flushCount += 1
            spliceTime = nil
        #endif
        nextEnqueueTime = .invalid
        firstSpliceBuffer = nil
        cursor?.cancel()
        cursor = nil
    }

    private func feed() {
        guard let cursor else { return }
        do {
            while renderer.isReadyForMoreMediaData {
                let next = try firstSpliceBuffer ?? cursor.nextBuffer()
                firstSpliceBuffer = nil
                guard let buffer = next else {
                    reachedEnd = true
                    renderer.stopRequestingMediaData()
                    break
                }
                renderer.enqueue(buffer)
                nextEnqueueTime = buffer.outputPresentationTimeStamp + buffer.outputDuration
                if requested, clock.rate == 0 {
                    clock.rate = 1
                    event(generation, .playing)
                }
            }
        } catch {
            fail()
        }
    }

    private func observe(_ position: CMTime) {
        guard let source else { return }
        if renderer.status == .failed { fail(); return }
        time(generation, position.seconds)
        if requested, reachedEnd, position.seconds >= source.duration {
            stopReading()
            self.source = nil
            event(generation, .ended)
        }
    }

    private func fail() {
        stopReading()
        source = nil
        event(generation, .failed)
    }

    deinit {
        if let flushObserver { NotificationCenter.default.removeObserver(flushObserver) }
        if let observation { clock.removeTimeObserver(observation) }
        renderer.stopRequestingMediaData()
        renderer.flush()
    }
}

@MainActor
final class AirPlaySampleSession {
    private let operations = AirPlaySongOperations()
    private var source: AirPlaySampleSource?
    private var loading: Task<Void, Never>?
    private var preparation: Task<Void, Never>?
    private var submittingTransition = false
    private var timeout: Task<Void, Never>?
    private var renderer: AirPlaySampleRenderer?
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var pendingPlan: TransitionCoordinator.TransitionPlan?
    var isOverlapping: Bool {
        guard let timing = source?.timing, pendingPlan != nil else { return false }
        return position + offset >= timing.overlapStart
    }
    private var offset: Double = 0
    private var wantsPlayback = false
    private var awaitingStart = false
    private let onEvent: @MainActor (AirPlaySampleRenderer.Event) -> Void
    private let onTime: @MainActor (Double, TransitionCoordinator.TransitionPlan?) -> Void

    init(
        onEvent: @escaping @MainActor (AirPlaySampleRenderer.Event) -> Void,
        onTime: @escaping @MainActor (Double, TransitionCoordinator.TransitionPlan?) -> Void
    ) {
        self.onEvent = onEvent
        self.onTime = onTime
        renderer = AirPlaySampleRenderer { [weak self] generation, event in
            Task { @MainActor in self?.receive(event, generation: generation) }
        } time: { [weak self] generation, time in
            Task { @MainActor in self?.receive(time: time, generation: generation) }
        }
    }

    func loadSong(_ url: URL, at time: Double, autoplay: Bool) {
        preparation?.cancel()
        submittingTransition = false
        loading?.cancel()
        timeout?.cancel()
        source = nil
        pendingPlan = nil
        offset = 0
        position = time
        wantsPlayback = autoplay
        awaitingStart = autoplay
        let generation = operations.begin()
        if autoplay { armTimeout(generation: generation) }
        renderer?.stop()
        loading = Task {
            do {
                let source = try await AirPlaySampleSource.song(url)
                guard !Task.isCancelled, operations.isCurrent(generation) else { return }
                duration = source.duration
                self.source = source
                renderer?.load(source, position: position, autoplay: wantsPlayback, generation: generation)
            } catch {
                guard !Task.isCancelled else { return }
                receive(.failed, generation: generation)
            }
        }
    }

    func prepareTransition(from outgoing: URL, plan: TransitionCoordinator.TransitionPlan, canInstall: @escaping @MainActor () -> Bool) {
        guard !submittingTransition, pendingPlan == nil else { return }
        preparation?.cancel()
        preparation = Task {
            let generation = operations.generation
            do {
                guard let source = try await AirPlaySampleSource.transition(
                          outgoing: outgoing, incoming: plan.nextFileURL, fade: plan.fadeDuration,
                          equalPower: plan.rampStyle == .equalPower, startingAt: offset
                      ), !Task.isCancelled, operations.isCurrent(generation), canInstall(),
                      let timing = source.timing, wantsPlayback, !awaitingStart,
                      position + offset < timing.overlapStart, let renderer else { return }
                submittingTransition = true
                let installed = await renderer.splice(source, generation: generation)
                guard !Task.isCancelled, operations.isCurrent(generation) else { return }
                submittingTransition = false
                guard installed else { return }
                guard canInstall() else {
                    loadSong(outgoing, at: position, autoplay: wantsPlayback)
                    return
                }
                pendingPlan = plan
                duration = timing.promotionTime - offset
                self.source = source
            } catch {
                DebugLogger.log("AirPlay sample transition failed: \(error)", category: .playback)
            }
        }
    }

    func cancelTransition(url: URL?) {
        preparation?.cancel()
        guard let url, submittingTransition || pendingPlan != nil else { return }
        loadSong(url, at: position, autoplay: wantsPlayback)
    }

    func pause() {
        wantsPlayback = false
        awaitingStart = false
        timeout?.cancel()
        renderer?.setPlaying(false)
    }

    func resume(url: URL) {
        guard !wantsPlayback else { return }
        if duration > 0, position >= duration {
            loadSong(url, at: 0, autoplay: true)
            return
        }
        wantsPlayback = true
        awaitingStart = true
        armTimeout()
        renderer?.setPlaying(true)
    }

    func stop(completion: (@Sendable () -> Void)? = nil) {
        operations.invalidate()
        preparation?.cancel()
        submittingTransition = false
        loading?.cancel()
        timeout?.cancel()
        renderer?.retire(completion: completion)
    }

    private func armTimeout(generation: Int? = nil) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, wantsPlayback, awaitingStart,
                  generation.map({ operations.isCurrent($0) }) ?? true else { return }
            onEvent(.failed)
        }
    }

    private func receive(_ event: AirPlaySampleRenderer.Event, generation: Int) {
        guard operations.isCurrent(generation) else { return }
        if case .playing = event, !wantsPlayback { return }
        if case .ended = event {
            wantsPlayback = false
            position = duration
        }
        timeout?.cancel()
        awaitingStart = false
        onEvent(event)
    }

    private func receive(time: Double, generation: Int) {
        guard operations.isCurrent(generation), time.isFinite else { return }
        var promoted: TransitionCoordinator.TransitionPlan?
        if let timing = source?.timing, let pendingPlan, time >= timing.promotionTime {
            promoted = pendingPlan
            self.pendingPlan = nil
            offset = timing.overlapStart
            duration = timing.incomingDuration
        }
        position = min(duration, max(0, time - offset))
        onTime(position, promoted)
    }
}
