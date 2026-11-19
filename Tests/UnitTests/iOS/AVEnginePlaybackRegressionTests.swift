import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import Twinskaraoke

@Suite("AVEngine playback regressions", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct AVEnginePlaybackRegressionTests {
    @Test("AirPlay automatically routes only ordinary file-backed songs")
    func airPlayAutomaticRouteSelection() {
        let local = URL(fileURLWithPath: "/tmp/song.wav")
        let remote = URL(string: "https://example.com/song.wav")
        #expect(AirPlaySongRouting.shouldRouteSong(outputs: [.builtInSpeaker, .airPlay], url: local, processingActive: false))
        #expect(!AirPlaySongRouting.shouldRouteSong(outputs: [.builtInSpeaker], url: local, processingActive: false))
        #expect(!AirPlaySongRouting.shouldRouteSong(outputs: [.airPlay], url: local, processingActive: true))
        #expect(!AirPlaySongRouting.shouldRouteSong(outputs: [.airPlay], url: remote, processingActive: false))
    }

    @Test("AirPlay transition overlaps the tracks and maps the incoming lyric clock")
    func airPlayTransitionTimeline() throws {
        let timing = try #require(AirPlayTransitionTiming(outgoing: 60, incoming: 40, fade: 8))
        #expect(timing.overlapStart == 52)
        #expect(timing.promotionTime == 60)
        #expect(timing.incomingTime(at: 60) == 8)
        #expect(timing.incomingTime(at: 65) == 13)
        #expect(AirPlayTransitionTiming(outgoing: 60, incoming: 3, fade: 8) == nil)
    }

    @Test("The AirPlay composition carries two overlapping audio tracks and a mix")
    func airPlayCompositionCarriesBothTracks() async throws {
        let outgoing = try makeSilentWaveFile(duration: 6, sampleRate: 48_000, tone: 440)
        defer { try? FileManager.default.removeItem(at: outgoing) }
        let incoming = try makeSilentWaveFile(duration: 5, sampleRate: 48_000, tone: 660)
        defer { try? FileManager.default.removeItem(at: incoming) }
        let result = try await AirPlayTransition.prepare(outgoing: outgoing, incoming: incoming, fade: 2, equalPower: true)
        let prepared = try #require(result)
        #expect(prepared.tracks.count == 2)
        #expect(prepared.duration == 9)
        #expect(prepared.mix.inputParameters.count == 2)
        #expect(prepared.timing.incomingTime(at: prepared.timing.promotionTime) == 2)
    }

    @Test("AirPlay sends the renderer PCM containing both songs during the fade")
    func airPlayMixedSamplesContainBothSongs() async throws {
        let outgoing = try makeSilentWaveFile(duration: 6, sampleRate: 48_000, tone: 440)
        defer { try? FileManager.default.removeItem(at: outgoing) }
        let incoming = try makeSilentWaveFile(duration: 5, sampleRate: 48_000, tone: 660)
        defer { try? FileManager.default.removeItem(at: incoming) }
        let prepared = try await AirPlaySampleSource.transition(outgoing: outgoing, incoming: incoming, fade: 2, equalPower: true)
        let source = try #require(prepared)
        let cursor = try source.makeCursor(at: CMTime(seconds: 5, preferredTimescale: 48_000))
        let buffer = try #require(try cursor.nextBuffer())
        let block = try #require(CMSampleBufferGetDataBuffer(buffer))
        let length = CMBlockBufferGetDataLength(block)
        var pcm = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        let status = pcm.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
        }
        #expect(status == kCMBlockBufferNoErr)
        let frames = stride(from: 0, to: pcm.count, by: 2).map { pcm[$0] }
        for frequency in [440.0, 660.0] {
            let energy = frames.enumerated().reduce(into: (real: 0.0, imaginary: 0.0)) { sum, frame in
                let phase = 2 * Double.pi * frequency * Double(frame.offset) / 48_000
                sum.real += Double(frame.element) * cos(phase)
                sum.imaginary += Double(frame.element) * sin(phase)
            }
            #expect(2 * hypot(energy.real, energy.imaginary) / Double(frames.count) > 0.04)
        }
    }

    @Test(
        "AirPlay splices a prepared mix onto the queued audio timeline",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func airPlaySplicePreservesQueuedAudio() async throws {
        let outgoing = try makeSilentWaveFile(duration: 60, sampleRate: 48_000)
        let incoming = try makeSilentWaveFile(duration: 45, sampleRate: 48_000)
        let playing = Mutex(false)
        let renderer = AirPlaySampleRenderer { _, event in
            if case .playing = event { playing.withLock { $0 = true } }
        } time: { _, _ in }
        defer {
            renderer.stop()
            try? FileManager.default.removeItem(at: outgoing)
            try? FileManager.default.removeItem(at: incoming)
        }

        let song = try await AirPlaySampleSource.song(outgoing)
        let prepared = try await AirPlaySampleSource.transition(outgoing: outgoing, incoming: incoming, fade: 2, equalPower: true)
        let mix = try #require(prepared)
        renderer.load(song, position: 20, autoplay: true, generation: 1)
        try await waitUntil { playing.withLock { $0 } }
        let initial = await renderer.stateForTesting()
        #expect(initial.rate == 1)
        #expect(await !renderer.splice(mix, generation: 0))
        #expect(await !renderer.splice(song, generation: 1))
        #expect(await renderer.splice(mix, generation: 1))
        let installed = await renderer.stateForTesting()
        #expect(installed.position >= initial.position)
        #expect(installed.rate == initial.rate)
        #expect(installed.flushCount == initial.flushCount)
        let spliceTime = try #require(installed.spliceTime)
        #expect(spliceTime >= initial.position)
        #expect(spliceTime < 58)

        renderer.load(song, position: 59, autoplay: false, generation: 2)
        let late = await renderer.stateForTesting()
        #expect(await !renderer.splice(mix, generation: 2))
        let rejected = await renderer.stateForTesting()
        #expect(rejected.position == late.position)
        #expect(rejected.flushCount == late.flushCount)
        #expect(rejected.spliceTime == nil)
    }

    @Test("Consecutive AirPlay mixes keep the renderer timeline and incoming track time aligned")
    func airPlayConsecutiveMixTimeline() async throws {
        let outgoing = try makeSilentWaveFile(duration: 6, sampleRate: 48_000)
        let incoming = try makeSilentWaveFile(duration: 5, sampleRate: 48_000)
        defer {
            try? FileManager.default.removeItem(at: outgoing)
            try? FileManager.default.removeItem(at: incoming)
        }

        let first = try #require(try await AirPlayTransition.prepare(
            outgoing: outgoing, incoming: incoming, fade: 2, equalPower: false
        ))
        let second = try #require(try await AirPlaySampleSource.transition(
            outgoing: incoming, incoming: outgoing, fade: 1, equalPower: true,
            startingAt: first.timing.overlapStart
        ))
        let timing = try #require(second.timing)
        #expect(timing.overlapStart == 8)
        #expect(timing.promotionTime == 9)
        #expect(timing.incomingTime(at: 9) == 1)
        #expect(second.duration == 14)
        let position = CMTime(value: 7 * 48_000 + 1, timescale: 48_000)
        let cursor = try second.makeCursor(at: position)
        let firstBuffer = try #require(try cursor.nextBuffer())
        #expect(firstBuffer.presentationTimeStamp == position)
    }

    @Test(
        "Cancelling AirPlay mix preparation leaves the current song playing",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func airPlayCancelsMixPreparation() async throws {
        let outgoing = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let incoming = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let nextSong = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"next","title":"Next"}"#.utf8))
        let plan = TransitionCoordinator.TransitionPlan(
            target: PlaybackQueueState.Entry(song: nextSong), nextFileURL: incoming,
            outgoingBPM: nil, incomingBPM: nil, fadeDuration: 0.25, rampStyle: .equalPower
        )
        var starts = 0
        var ended = false
        let session = AirPlaySampleSession { event in
            if case .playing = event { starts += 1 }
            if case .ended = event { ended = true }
        } onTime: { _, plan in
            #expect(plan == nil)
        }
        defer {
            session.stop()
            try? FileManager.default.removeItem(at: outgoing)
            try? FileManager.default.removeItem(at: incoming)
        }
        session.loadSong(outgoing, at: 0, autoplay: true)
        try await waitUntil { starts == 1 }
        session.prepareTransition(from: outgoing, plan: plan) {
            Issue.record("Cancelled preparation reached the installation check")
            return false
        }
        session.cancelTransition(url: outgoing)
        try await waitUntil { ended }
        #expect(starts == 1)
        #expect(session.pendingPlan == nil)
    }

    @Test("AirPlay accepts only the latest seek or handoff completion")
    func airPlayRejectsObsoleteOperations() {
        let session = AirPlaySongOperations()
        let oldSeek = session.begin()
        let latestSeek = session.begin()
        #expect(!session.isCurrent(oldSeek))
        #expect(session.isCurrent(latestSeek))
        session.invalidate()
        #expect(!session.isCurrent(latestSeek))
    }

    @Test(
        "AirPlay departure defers vocal effects until the destination engine is ready",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func airPlayDepartureDefersEffectsUntilLocalEngineIsReady() async throws {
        let source = try makeSilentWaveFile(duration: 10, sampleRate: 48_000)
        let engine = AVEnginePlayback()
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: source)
        }

        #expect(!AirPlayPlaybackCoordinator.canApplyEffects(
            usesAirPlayPlayer: false, handoffPending: true, loadingLocalEngine: false
        ))
        engine.play(url: source, startAt: 4, isAirPlayHandoff: true)
        #expect(engine.isLoadingAirPlayHandoff)
        #expect(!AirPlayPlaybackCoordinator.canApplyEffects(
            usesAirPlayPlayer: false, handoffPending: false, loadingLocalEngine: engine.isLoadingAirPlayHandoff
        ))
        try await waitUntil { engine.hasPlayableMainMedia }
        #expect(AirPlayPlaybackCoordinator.canApplyEffects(
            usesAirPlayPlayer: false, handoffPending: false, loadingLocalEngine: engine.isLoadingAirPlayHandoff
        ))
        #expect(engine.currentTime >= 4)
    }

    @Test(
        "An AirPlay song can play again after reaching the end of the queue",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func airPlaySampleSessionRestartsAfterEnding() async throws {
        let source = try makeSilentWaveFile(duration: 0.4, sampleRate: 48_000)
        var starts = 0
        var ends = 0
        let session = AirPlaySampleSession { event in
            if case .playing = event { starts += 1 }
            if case .ended = event { ends += 1 }
        } onTime: { _, _ in }
        defer {
            session.stop()
            try? FileManager.default.removeItem(at: source)
        }

        session.loadSong(source, at: 0, autoplay: true)
        try await waitUntil { ends == 1 }
        session.resume(url: source)
        #expect(session.position == 0)
        try await waitUntil { starts == 2 }
    }

    @Test("A superseded AirPlay departure cannot start its destination after the drain")
    func supersededAirPlayDepartureCannotRestart() async {
        let operations = AirPlaySongOperations()
        let first = operations.begin()
        let drain = Task { await operations.waitForOutputDrain(first) }
        await Task.yield()

        let second = operations.begin()
        #expect(await !drain.value)
        operations.invalidate()
        #expect(await !operations.waitForOutputDrain(second))
    }

    @Test("Repeated AirPlay retirement completes every handoff waiter")
    func repeatedAirPlayRetirementCompletesWaiters() async throws {
        let renderer = AirPlaySampleRenderer(event: { _, _ in }, time: { _, _ in })
        let completed = Mutex(0)
        #expect(await !renderer.isMutedForTesting())
        renderer.retire(completion: nil)
        renderer.retire { completed.withLock { $0 += 1 } }
        renderer.retire { completed.withLock { $0 += 1 } }

        try await waitUntil { completed.withLock { $0 == 2 } }
        #expect(await renderer.isMutedForTesting())
    }

    @Test(
        "The local clock holds its resume position while a song loads",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func localClockHoldsResumePositionDuringLoad() async throws {
        let source = try makeSilentWaveFile(duration: 10, sampleRate: 48_000)
        let engine = AVEnginePlayback()
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: source)
        }

        engine.play(url: source, startAt: 4)
        #expect(engine.currentTime == 4)
        try await waitUntil { engine.hasPlayableMainMedia }
        #expect(engine.currentTime >= 4)

        engine.stop()
        #expect(engine.currentTime == 0)
    }

    @Test("Stopping a scheduled player does not report natural playback end")
    func teardownCompletionIsSuppressed() throws {
        let sourceURL = try makeSilentWaveFile(duration: 10, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let player = SimpleAudioPlayer()
        let file = try AVAudioFile(forReading: sourceURL)

        var completionCount = 0
        player.completionHandler = { completionCount += 1 }
        try player.load(file: file)
        let scheduledGeneration = player.scheduleGenerationForTesting
        player.stop()
        player.deliverCompletionForTesting(scheduledGeneration: scheduledGeneration)

        #expect(player.scheduleGenerationForTesting != scheduledGeneration)
        #expect(completionCount == 0)
    }

    @Test("File-backed playback preserves the source processing format")
    func nativeSourceFormatIsRetained() throws {
        let sourceURL = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let player = SimpleAudioPlayer()
        try player.load(file: AVAudioFile(forReading: sourceURL))

        #expect(player.loadedFileFormatForTesting?.sampleRate == 48_000)
        #expect(player.loadedFileFormatForTesting?.channelCount == 2)
        #expect(abs(player.duration - 2) < 0.01)
    }

    @Test("Starting at end of file reports completion without phantom playback")
    func endOfFileStartCompletes() async throws {
        let sourceURL = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let player = SimpleAudioPlayer()
        try player.load(file: AVAudioFile(forReading: sourceURL))

        var completionCount = 0
        await confirmation("end-of-file completion fires once", expectedCount: 1) { completion in
            // The completion is delivered through a MainActor task hop, so the
            // body must suspend until it fires: confirmation() checks the
            // count as soon as its body returns and does not wait on its own.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var didResume = false
                player.completionHandler = {
                    completionCount += 1
                    completion()
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume()
                }
                player.play(from: player.duration)
            }
        }

        #expect(!player.isPlaying)
        #expect(completionCount == 1)
    }

    @Test("Seek while paused then resume continues from the seek target")
    func pausedSeekThenResumeKeepsPosition() async throws {
        let sourceURL = try makeSilentWaveFile(duration: 10, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let engine = AVEnginePlayback()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.play(url: sourceURL, onReady: { continuation.resume() })
        }

        engine.pause()
        #expect(engine.seek(to: 5))
        // The seek must not leave the decks playing behind the paused facade.
        #expect(!engine.isPlaying)
        #expect(abs(engine.currentTime - 5) < 0.5)

        // Regression: resume used to fall through to play(from: 0) because
        // the seek's internal stop()/play() had cleared the paused state.
        engine.resume()
        #expect(engine.currentTime >= 4.5)
        engine.stop()
    }

    @Test(
        "Crossfade promotes the incoming track and clears transition state",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func crossfadeCompletesHandoff() async throws {
        let sourceURL = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let incomingURL = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: incomingURL)
        }

        let engine = AVEnginePlayback()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.play(url: sourceURL, onReady: { continuation.resume() })
        }

        await confirmation("crossfade completes", expectedCount: 1) { completion in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                engine.onCrossfadeCompleted = {
                    completion()
                    continuation.resume()
                }
                engine.beginCrossfade(url: incomingURL, duration: 0.5, ramp: .linear)
            }
        }

        #expect(!engine.isCrossfading)
        #expect(engine.currentURL == incomingURL)
        #expect(!engine.isCrossfadePending)
        engine.stop()
    }

    @Test(
        "An unavailable incoming file leaves the outgoing song playing",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func crossfadeLoadFailureDoesNotEndOutgoingPlayback() async throws {
        let sourceURL = try makeSilentWaveFile(duration: 4, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let missingURL = sourceURL.appendingPathExtension("missing")
        let attempted = Mutex<URL?>(nil)
        let engine = AVEnginePlayback { url in
            attempted.withLock { $0 = url }
            return try AVAudioFile(forReading: url)
        }
        defer { engine.stop() }
        await withCheckedContinuation { continuation in
            engine.play(url: sourceURL, onReady: { continuation.resume() })
        }

        var playbackErrors = 0
        engine.onPlaybackError = { _ in playbackErrors += 1 }
        engine.beginCrossfade(url: missingURL, duration: 1, ramp: .linear)
        try await waitUntil { attempted.withLock { $0 } == missingURL && !engine.isCrossfadePending }

        #expect(playbackErrors == 0)
        #expect(!engine.isCrossfadePending)
        #expect(engine.currentURL == sourceURL)
        #expect(engine.isPlaying)
    }

    @Test(
        "A late crossfade reuses the incoming load and keeps the mixer audible",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func lateCrossfadeReusesLoad() async throws {
        let outgoing = try makeSilentWaveFile(duration: 3, sampleRate: 48_000, tone: 440)
        let incoming = try makeSilentWaveFile(duration: 2, sampleRate: 48_000, tone: 660)
        let load = GatedLoad()
        let engine = AVEnginePlayback(crossfadeFileLoader: load.open)
        let capture = MixerCapture()
        let mixer = engine.crossfadeMixerForTesting
        mixer.installTap(onBus: 0, bufferSize: 256, format: nil) { @Sendable buffer, _ in
            capture.append(buffer)
        }
        defer {
            load.release()
            mixer.removeTap(onBus: 0)
            engine.stop()
            for url in [outgoing, incoming] { try? FileManager.default.removeItem(at: url) }
        }

        await withCheckedContinuation { continuation in
            engine.play(url: outgoing, onReady: { continuation.resume() })
        }
        engine.preloadCrossfade(url: incoming)
        try await waitUntil { load.count == 1 && engine.currentTime >= 0.5 }
        var scheduledDuration: TimeInterval?
        engine.onCrossfadeScheduled = { scheduledDuration = $0 }
        engine.onPlaybackEnded = { [weak engine] in
            engine?.finishPreparedCrossfade(to: incoming)
        }
        engine.beginCrossfade(url: incoming, duration: 0.6, ramp: .linear, remainingTime: { 0.35 })
        load.release()
        try await waitUntil { engine.currentURL == incoming && engine.currentTime >= 0.45 }
        #expect(load.count == 1)
        #expect(try #require(scheduledDuration) < 0.6)
        let windows = capture.audibleWindows
        let first = try #require(windows.firstIndex(of: true))
        #expect(windows[first...].allSatisfy { $0 })
        #expect(capture.endsWithTone(660, rejecting: 440))
    }

    @Test(
        "A ready incoming deck can be promoted at natural end without scheduling a fade",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func readyDeckAtNaturalEnd() async throws {
        let outgoing = try makeSilentWaveFile(duration: 1.5, sampleRate: 48_000)
        let incoming = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let engine = AVEnginePlayback()
        defer {
            engine.stop()
            for url in [outgoing, incoming] { try? FileManager.default.removeItem(at: url) }
        }
        await withCheckedContinuation { continuation in
            engine.play(url: outgoing, onReady: { continuation.resume() })
        }
        var scheduled = false
        var handedOff = false
        engine.onCrossfadeScheduled = { _ in scheduled = true }
        engine.onPlaybackEnded = { [weak engine] in
            handedOff = engine?.finishPreparedCrossfade(to: incoming) == true
        }
        engine.beginCrossfade(url: incoming, duration: 1, ramp: .linear, remainingTime: { 0 })
        try await waitUntil { handedOff }
        #expect(!scheduled)
        #expect(engine.currentURL == incoming)
        #expect(!engine.isCrossfadePending)
    }

    @Test(
        "Natural end is delivered while the incoming load is pending and cancellation fences its result",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func lateLoadCanBeCancelledAtNaturalEnd() async throws {
        let outgoing = try makeSilentWaveFile(duration: 1.5, sampleRate: 48_000)
        let incoming = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let load = GatedLoad()
        let engine = AVEnginePlayback(crossfadeFileLoader: load.open)
        defer {
            load.release()
            engine.stop()
            for url in [outgoing, incoming] { try? FileManager.default.removeItem(at: url) }
        }
        await withCheckedContinuation { continuation in
            engine.play(url: outgoing, onReady: { continuation.resume() })
        }
        var advances = 0
        engine.onPlaybackEnded = { [weak engine] in
            guard let engine else { return }
            #expect(!engine.finishPreparedCrossfade(to: incoming))
            engine.cancelCrossfade()
            advances += 1
        }
        engine.beginCrossfade(url: incoming, duration: 1, ramp: .linear)
        try await waitUntil { load.count == 1 && advances == 1 }
        var schedules = 0
        engine.onCrossfadeScheduled = { _ in schedules += 1 }
        engine.beginCrossfade(url: incoming, duration: 0.5, ramp: .linear, remainingTime: { 0 })
        try await waitUntil { load.count == 2 }
        load.release()
        load.release()
        var promoted = false
        try await waitUntil {
            if !promoted { promoted = engine.finishPreparedCrossfade(to: incoming) }
            return promoted
        }
        #expect(engine.currentURL == incoming)
        #expect(schedules == 0)
        #expect(advances == 1)
    }

    @Test(
        "An exhausted incoming deck cannot replace playable outgoing audio",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func exhaustedIncomingDeckAbortsCrossfade() async throws {
        let outgoing = try makeSilentWaveFile(duration: 4, sampleRate: 48_000)
        let incoming = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let engine = AVEnginePlayback()
        defer {
            engine.stop()
            for url in [outgoing, incoming] { try? FileManager.default.removeItem(at: url) }
        }
        await withCheckedContinuation { continuation in
            engine.play(url: outgoing, onReady: { continuation.resume() })
        }
        var aborted = 0
        engine.onCrossfadeAborted = { aborted += 1 }
        engine.beginCrossfade(url: incoming, duration: 0.5, ramp: .linear)
        try await waitUntil { engine.hasAudibleCrossfade }
        engine.expireIncomingDeckForTesting()
        #expect(aborted == 1)
        #expect(engine.currentURL == outgoing)
        #expect(engine.hasPlayableMainMedia)
        #expect(!engine.finishPreparedCrossfade(to: incoming))
    }

    @Test(
        "Recovery ignores stale scheduled media and invalidates both old callbacks",
        .enabled(if: audioOutputAvailable, "Needs an audio output device.")
    )
    func recoveryInvalidatesDeadlineAndWatchdog() async throws {
        let outgoing = try makeSilentWaveFile(duration: 4, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: outgoing) }
        let engine = AVEnginePlayback()
        defer { engine.stop() }
        await withCheckedContinuation { continuation in
            engine.play(url: outgoing, onReady: { continuation.resume() })
        }

        let transition = PlaybackTransition()
        #expect(!transition.recover(engine: engine))
        engine.pause()
        try #require(engine.hasScheduledMedia)
        var staleCallbacks = 0
        transition.scheduleDeadline(after: 0) { staleCallbacks += 1 }
        transition.scheduleWatchdog(after: 0) { staleCallbacks += 1 }
        #expect(transition.recover(engine: engine))
        await withCheckedContinuation { continuation in
            transition.scheduleDeadline(after: 0) { continuation.resume() }
        }
        #expect(staleCallbacks == 0)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(predicate())
    }

    private func makeSilentWaveFile(duration: TimeInterval, sampleRate: Double, tone: Double? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("playback-regression-\(UUID().uuidString).wav")
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        for channel in 0 ..< 2 {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0 ..< Int(frameCount) {
                samples[frame] = tone.map { Float(0.2 * sin(2 * .pi * $0 * Double(frame) / sampleRate)) } ?? 0
            }
        }
        let writer = try AVAudioFile(forWriting: url, settings: format.settings)
        try writer.write(from: buffer)
        return url
    }
}

private nonisolated final class GatedLoad: Sendable {
    private let opens = Mutex(0)
    private let gate = DispatchSemaphore(value: 0)

    var count: Int { opens.withLock { $0 } }

    func open(_ url: URL) throws -> AVAudioFile {
        opens.withLock { $0 += 1 }
        _ = gate.wait(timeout: .now() + 5)
        return try AVAudioFile(forReading: url)
    }

    func release() { gate.signal() }
}

private nonisolated final class MixerCapture: Sendable {
    private let samples = Mutex<[Float]>([])

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        samples.withLock { $0.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))) }
    }

    func endsWithTone(_ incoming: Double, rejecting outgoing: Double) -> Bool {
        let tail = samples.withLock { Array($0.suffix(2_400)) }
        guard tail.count == 2_400 else { return false }
        func amplitude(at frequency: Double) -> Double {
            let angularFrequency = 2 * Double.pi * frequency / 48_000
            let components = tail.enumerated().reduce(into: (sine: 0.0, cosine: 0.0)) { result, pair in
                let angle = angularFrequency * Double(pair.offset)
                result.sine += sin(angle) * Double(pair.element)
                result.cosine += cos(angle) * Double(pair.element)
            }
            return 2 * hypot(components.sine, components.cosine) / Double(tail.count)
        }
        return amplitude(at: incoming) > 0.05 && amplitude(at: outgoing) < 0.01
    }

    var audibleWindows: [Bool] {
        let captured = samples.withLock { $0 }
        // Five milliseconds per window at 48 kHz, with a -60 dBFS threshold.
        return stride(from: 0, to: max(0, captured.count - 239), by: 240).map { start in
            captured[start ..< start + 240].reduce(0.0) { $0 + Double($1 * $1) } / 240 > 0.000001
        }
    }
}
