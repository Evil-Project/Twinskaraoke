import AVFoundation
import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Transition coordinator")
struct TransitionCoordinatorTests {
    @Test("Auto Mix uses a beat-aligned equal-power fade for close tempos")
    func autoMixFadeForCloseTempos() {
        let result = TransitionCoordinator.computeFade(outBPM: 120, inBPM: 124)

        #expect(result.duration == 8.0)
        #expect(isEqualPower(result.style))
    }

    @Test("Auto Mix uses a short linear cut for incompatible tempos")
    func autoMixFadeForDistantTempos() {
        let result = TransitionCoordinator.computeFade(outBPM: 120, inBPM: 87)

        #expect(result.duration == 1.5)
        #expect(isLinear(result.style))
    }

    @Test("Auto Mix falls back to a music-style crossfade when BPM is unavailable")
    func autoMixFadeWithoutBPM() {
        let result = TransitionCoordinator.computeFade(outBPM: nil, inBPM: 120)

        #expect(result.duration == 6.0)
        #expect(isEqualPower(result.style))
    }

    @Test("Auto Mix rejects invalid cached tempos")
    func autoMixFadeWithInvalidBPM() {
        let zero = TransitionCoordinator.computeFade(outBPM: 0, inBPM: 120)
        let nonFinite = TransitionCoordinator.computeFade(outBPM: .infinity, inBPM: 120)

        #expect(zero.duration == 6.0)
        #expect(isEqualPower(zero.style))
        #expect(nonFinite.duration == 6.0)
        #expect(isEqualPower(nonFinite.style))
    }

    @Test("Harmonic BPM comparison treats double-time tempos as compatible")
    func harmonicBPMDifferenceUsesDoubleTime() {
        #expect(TransitionCoordinator.harmonicBPMDifference(90, 180) == 0)
        #expect(TransitionCoordinator.harmonicBPMDifference(120, 62) == 4)
    }

    private func isEqualPower(_ style: AVEnginePlayback.RampStyle) -> Bool {
        if case .equalPower = style { return true }
        return false
    }

    private func isLinear(_ style: AVEnginePlayback.RampStyle) -> Bool {
        if case .linear = style { return true }
        return false
    }
}

@Suite("Playback schedule completion ownership")
struct PlaybackScheduleGateTests {
    @Test("A delayed completion cannot end a replacement schedule")
    func staleCompletionIsRejected() {
        var gate = PlaybackScheduleGate()
        let replacedGeneration = gate.beginSchedule()
        let activeGeneration = gate.beginSchedule()

        let acceptedReplacedCompletion = gate.consume(replacedGeneration)
        let acceptedActiveCompletion = gate.consume(activeGeneration)

        #expect(!acceptedReplacedCompletion)
        #expect(acceptedActiveCompletion)
    }

    @Test("A schedule completion is handled at most once")
    func duplicateCompletionIsRejected() {
        var gate = PlaybackScheduleGate()
        let generation = gate.beginSchedule()

        let acceptedFirstCompletion = gate.consume(generation)
        let acceptedDuplicateCompletion = gate.consume(generation)

        #expect(acceptedFirstCompletion)
        #expect(!acceptedDuplicateCompletion)
    }

    @Test("Stopping invalidates the scheduled completion")
    func invalidatedCompletionIsRejected() {
        var gate = PlaybackScheduleGate()
        let generation = gate.beginSchedule()

        gate.invalidate()
        let acceptedInvalidatedCompletion = gate.consume(generation)

        #expect(!acceptedInvalidatedCompletion)
    }
}

@Suite("Transition ramp completion ownership")
struct TransitionRampCompletionGateTests {
    @Test("Timer and fallback can complete a ramp only once")
    func timerAndFallbackCompleteOnce() {
        var gate = TransitionRampCompletionGate()
        let generation = gate.begin()

        let timerWon = gate.consume(generation)
        let fallbackWasRejected = gate.consume(generation)

        #expect(timerWon)
        #expect(!fallbackWasRejected)
    }

    @Test("A replacement ramp rejects the previous completion")
    func replacementRejectsStaleCompletion() {
        var gate = TransitionRampCompletionGate()
        let replaced = gate.begin()
        let active = gate.begin()

        let staleWasAccepted = gate.consume(replaced)
        #expect(gate.owns(active))
        let activeWasAccepted = gate.consume(active)

        #expect(!staleWasAccepted)
        #expect(activeWasAccepted)
    }

    @Test("Cancellation rejects both timer and fallback completion")
    func cancellationRejectsCompletion() {
        var gate = TransitionRampCompletionGate()
        let generation = gate.begin()

        gate.invalidate()

        let cancelledWasAccepted = gate.consume(generation)
        #expect(!gate.owns(generation))
        #expect(!cancelledWasAccepted)
    }
}

@Suite("AI stem load ownership")
struct StemLoadOwnershipGateTests {
    @Test("A replacement request invalidates the previous stem load")
    func replacementInvalidatesPreviousRequest() {
        var gate = StemLoadOwnershipGate()
        let replaced = gate.begin(recovery: .reloadOriginal)
        let active = gate.begin(recovery: .preserveMainPlayback)

        #expect(!gate.owns(replaced))
        #expect(gate.owns(active))
    }

    @Test("Cancellation reports whether main playback must be restored")
    func cancellationReturnsRecoveryPolicy() {
        var gate = StemLoadOwnershipGate()
        let fullStemStart = gate.begin(recovery: .reloadOriginal)
        let fullStemRecovery = gate.cancel()

        #expect(fullStemRecovery == .reloadOriginal)
        #expect(!gate.owns(fullStemStart))

        _ = gate.begin(recovery: .preserveMainPlayback)
        let switchRecovery = gate.cancel()
        #expect(switchRecovery == .preserveMainPlayback)
    }

    @Test("A completed stem load can be consumed only once")
    func completedRequestIsConsumedOnce() {
        var gate = StemLoadOwnershipGate()
        let request = gate.begin(recovery: .preserveMainPlayback)

        let acceptedFirstCompletion = gate.consume(request)
        let acceptedDuplicateCompletion = gate.consume(request)

        #expect(acceptedFirstCompletion)
        #expect(!acceptedDuplicateCompletion)
    }
}

@Suite("Vocal separation job ownership")
struct SeparationJobGateTests {
    @Test("A stale same-song job cannot finish its replacement")
    func staleSameSongCompletionIsRejected() {
        var gate = SeparationJobGate()
        let replaced = gate.begin(songID: "same-song")
        let active = gate.begin(songID: "same-song")
        let acceptedStaleCompletion = gate.finish(replaced)
        let acceptedActiveCompletion = gate.finish(active)

        #expect(!acceptedStaleCompletion)
        #expect(acceptedActiveCompletion)
    }

    @Test("Cancellation invalidates the active job")
    func cancellationInvalidatesActiveJob() {
        var gate = SeparationJobGate()
        let job = gate.begin(songID: "song")
        let cancelledJob = gate.cancel()

        #expect(cancelledJob == job)
        #expect(!gate.owns(job))
        let acceptedCancelledCompletion = gate.finish(job)
        #expect(!acceptedCancelledCompletion)
    }

    @Test("A completed job can be consumed only once")
    func completionIsConsumedOnce() {
        var gate = SeparationJobGate()
        let job = gate.begin(songID: "song")
        let acceptedFirstCompletion = gate.finish(job)
        let acceptedDuplicateCompletion = gate.finish(job)

        #expect(acceptedFirstCompletion)
        #expect(!acceptedDuplicateCompletion)
    }

    @Test("A stale job cannot commit over its replacement")
    func staleCommitIsRejectedBeforePublication() {
        var gate = SeparationJobGate()
        let stale = gate.begin(songID: "same-song")
        let replacement = gate.begin(songID: "same-song")
        var publishedValue = "winner"

        let acceptedStaleCommit = gate.finish(stale) {
            publishedValue = "stale"
        }

        #expect(!acceptedStaleCommit)
        #expect(publishedValue == "winner")
        #expect(gate.owns(replacement))

        let acceptedReplacementCommit = gate.finish(replacement) {
            publishedValue = "replacement"
        }
        #expect(acceptedReplacementCommit)
        #expect(publishedValue == "replacement")
    }

    @Test("A failed commit leaves the active job owned")
    func failedCommitRetainsOwnership() {
        struct CommitFailure: Error {}

        var gate = SeparationJobGate()
        let job = gate.begin(songID: "song")
        var didThrow = false

        do {
            _ = try gate.finish(job) {
                throw CommitFailure()
            }
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(gate.owns(job))
        let acceptedCleanup = gate.finish(job)
        #expect(acceptedCleanup)
    }

    @Test("Only the owning job can publish both stem files")
    func onlyOwnerPublishesStemFiles() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "SeparationJobGateTests.\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let vocalsDestination = root.appendingPathComponent("vocals.wav")
        let instrumentsDestination = root.appendingPathComponent("instruments.wav")
        try Data("winner-vocals".utf8).write(to: vocalsDestination)
        try Data("winner-instruments".utf8).write(to: instrumentsDestination)

        var gate = SeparationJobGate()
        let stale = gate.begin(songID: "same-song")
        let replacement = gate.begin(songID: "same-song")
        let staleVocals = root.appendingPathComponent("stale-vocals.wav")
        let staleInstruments = root.appendingPathComponent("stale-instruments.wav")
        try Data("stale-vocals".utf8).write(to: staleVocals)
        try Data("stale-instruments".utf8).write(to: staleInstruments)

        let acceptedStaleCommit = try gate.finish(stale) {
            try replace(staleVocals, at: vocalsDestination, using: fileManager)
            try replace(staleInstruments, at: instrumentsDestination, using: fileManager)
        }

        #expect(!acceptedStaleCommit)
        #expect(try String(contentsOf: vocalsDestination, encoding: .utf8) == "winner-vocals")
        #expect(try String(contentsOf: instrumentsDestination, encoding: .utf8) == "winner-instruments")

        let replacementVocals = root.appendingPathComponent("replacement-vocals.wav")
        let replacementInstruments = root.appendingPathComponent("replacement-instruments.wav")
        try Data("replacement-vocals".utf8).write(to: replacementVocals)
        try Data("replacement-instruments".utf8).write(to: replacementInstruments)
        let acceptedReplacementCommit = try gate.finish(replacement) {
            try replace(replacementVocals, at: vocalsDestination, using: fileManager)
            try replace(replacementInstruments, at: instrumentsDestination, using: fileManager)
        }

        #expect(acceptedReplacementCommit)
        #expect(try String(contentsOf: vocalsDestination, encoding: .utf8) == "replacement-vocals")
        #expect(try String(contentsOf: instrumentsDestination, encoding: .utf8) == "replacement-instruments")
    }

    private func replace(_ source: URL, at destination: URL, using fileManager: FileManager) throws {
        try fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: source, to: destination)
    }
}

@Suite("Vocal separation staging cleanup")
struct VocalSeparationStagingCleanupTests {
    @Test("Startup cleanup removes owned staging files without touching unrelated audio")
    func cleanupRemovesOnlyOwnedStagingFiles() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "VocalSeparatorTests.\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let persistentDirectory = root.appending(
            path: "VocalSeparationStaging",
            directoryHint: .isDirectory
        )
        let realtimeDirectory = root.appending(
            path: "RealtimeStems",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: persistentDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: realtimeDirectory, withIntermediateDirectories: true)

        let token = UUID().uuidString
        let abandonedURLs = [
            root.appending(path: "\(token).vocals.wav"),
            root.appending(path: "\(token).instruments.wav"),
            root.appending(path: "song.\(token).rt.trim.m4a"),
            persistentDirectory.appending(path: "partial.wav"),
            realtimeDirectory.appending(path: "partial.m4a"),
        ]
        for url in abandonedURLs {
            try Data("partial".utf8).write(to: url)
        }
        let unrelatedURL = root.appending(path: "mix.vocals.wav")
        try Data("keep".utf8).write(to: unrelatedURL)

        VocalSeparator.cleanupAbandonedStagingFiles(in: root, fileManager: fileManager)

        #expect(abandonedURLs.allSatisfy { !fileManager.fileExists(atPath: $0.path) })
        #expect(fileManager.fileExists(atPath: unrelatedURL.path))
        #expect(
            try fileManager.contentsOfDirectory(atPath: persistentDirectory.path).isEmpty
        )
        #expect(
            try fileManager.contentsOfDirectory(atPath: realtimeDirectory.path).isEmpty
        )
    }

    @Test("A temporary stem lease removes only its files and cleans once")
    func temporaryStemLeaseCleansExactlyOnce() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "TemporaryStemFileLeaseTests.\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let vocalsURL = root.appending(path: "vocals.wav")
        let instrumentsURL = root.appending(path: "instruments.wav")
        let unrelatedURL = root.appending(path: "keep.wav")
        for url in [vocalsURL, instrumentsURL, unrelatedURL] {
            try Data("audio".utf8).write(to: url)
        }

        let lease = TemporaryStemFileLease(
            urls: [vocalsURL, instrumentsURL, vocalsURL],
            fileManager: fileManager
        )

        #expect(lease.ownedURLs == [vocalsURL, instrumentsURL])
        #expect(lease.cleanup())
        #expect(!lease.cleanup())
        #expect(lease.isCleaned)
        #expect(!fileManager.fileExists(atPath: vocalsURL.path))
        #expect(!fileManager.fileExists(atPath: instrumentsURL.path))
        #expect(fileManager.fileExists(atPath: unrelatedURL.path))
    }

    @Test("Dropping an unhanded temporary result removes stems and trim output")
    func abandonedTemporaryStemLeaseCleansOnDeinit() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "AbandonedStemLeaseTests.\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let vocalsURL = root.appending(path: "vocals.wav")
        let instrumentsURL = root.appending(path: "instruments.wav")
        let trimURL = root.appending(path: "source.trim.m4a")
        let ownedURLs = [vocalsURL, instrumentsURL, trimURL]
        for url in ownedURLs {
            try Data("partial".utf8).write(to: url)
        }

        var lease: TemporaryStemFileLease? = TemporaryStemFileLease(
            vocals: vocalsURL,
            instruments: instrumentsURL,
            trimmedSource: trimURL,
            fileManager: fileManager
        )
        #expect(lease?.ownedURLs == ownedURLs)
        #expect(lease != nil)
        lease = nil

        #expect(ownedURLs.allSatisfy { !fileManager.fileExists(atPath: $0.path) })
    }

    @Test("Persistent cached stems never retain a temporary file lease")
    func persistentCachedStemsIgnoreTemporaryLease() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "PersistentStemLeaseTests.\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let vocalsURL = root.appending(path: "vocals.wav")
        let instrumentsURL = root.appending(path: "instruments.wav")
        try Data("audio".utf8).write(to: vocalsURL)
        try Data("audio".utf8).write(to: instrumentsURL)

        do {
            let stems = CachedStems(
                vocals: vocalsURL,
                instruments: instrumentsURL,
                startOffset: 0,
                isTemporary: false
            )
            #expect(stems.temporaryLease == nil)
        }

        #expect(fileManager.fileExists(atPath: vocalsURL.path))
        #expect(fileManager.fileExists(atPath: instrumentsURL.path))
    }
}

@Suite("Temporary stem playback cleanup")
struct TemporaryStemPlaybackCleanupTests {
    @Test("Stopping a pending stem handoff cleans its temporary files")
    @MainActor
    func stoppingPendingHandoffCleansLease() throws {
        let fixture = try makeAudioFixture()
        defer { fixture.cleanup() }
        let lease = TemporaryStemFileLease(
            vocals: fixture.vocals,
            instruments: fixture.instruments
        )
        let playback = AVEnginePlayback()

        playback.switchToStems(
            vocalsURL: fixture.vocals,
            instrumentsURL: fixture.instruments,
            startOffset: 0,
            temporaryLease: lease
        )
        playback.stop()

        #expect(lease.isCleaned)
        #expect(!FileManager.default.fileExists(atPath: fixture.vocals.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.instruments.path))
    }

    @Test("Reverting active temporary stems releases their files")
    @MainActor
    func revertingActiveTemporaryStemsCleansLease() async throws {
        let fixture = try makeAudioFixture()
        defer { fixture.cleanup() }
        let lease = TemporaryStemFileLease(
            vocals: fixture.vocals,
            instruments: fixture.instruments
        )
        let playback = AVEnginePlayback()

        var originalReady = false
        playback.play(
            url: fixture.original,
            shouldPlay: { false },
            onReady: { originalReady = true }
        )
        await waitFor { originalReady }
        guard originalReady else {
            playback.stop()
            Issue.record("Original test media did not load")
            return
        }

        var stemsReady = false
        playback.switchToStems(
            vocalsURL: fixture.vocals,
            instrumentsURL: fixture.instruments,
            startOffset: 0,
            temporaryLease: lease,
            shouldPlay: { false },
            onReady: { stemsReady = true }
        )
        await waitFor { stemsReady }
        guard stemsReady else {
            playback.stop()
            Issue.record("Temporary test stems did not load")
            return
        }

        #expect(!lease.isCleaned)
        playback.revertToMain()

        #expect(lease.isCleaned)
        #expect(!FileManager.default.fileExists(atPath: fixture.vocals.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.instruments.path))
        playback.stop()
    }

    private struct AudioFixture {
        let root: URL
        let original: URL
        let vocals: URL
        let instruments: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeAudioFixture() throws -> AudioFixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "TemporaryStemPlaybackTests.\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fixture = AudioFixture(
            root: root,
            original: root.appending(path: "original.wav"),
            vocals: root.appending(path: "vocals.wav"),
            instruments: root.appending(path: "instruments.wav")
        )
        do {
            try writeSilentStereoAudio(to: fixture.original)
            try writeSilentStereoAudio(to: fixture.vocals)
            try writeSilentStereoAudio(to: fixture.instruments)
            return fixture
        } catch {
            fixture.cleanup()
            throw error
        }
    }

    private func writeSilentStereoAudio(to url: URL) throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44_100,
                channels: 2,
                interleaved: false
            )
        )
        let frameCount: AVAudioFrameCount = 4_410
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        if let channels = buffer.floatChannelData {
            for channel in 0 ..< Int(format.channelCount) {
                channels[channel].initialize(repeating: 0, count: Int(frameCount))
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@Suite("Audio cache main ownership")
struct AudioCacheMainOwnershipTests {
    @Test("A replacement writer prevents an older writer from publishing")
    func latestStartedWriterWins() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let old = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("old.mp3")
        )
        try fixture.stage("old-main", for: old)
        let replacement = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("new.mp3")
        )
        try fixture.stage("new-main", for: replacement)

        let replacementCommitted = try fixture.ownership.commit(replacement)
        let oldCommitted = try fixture.ownership.commit(old)

        #expect(replacementCommitted)
        #expect(!oldCommitted)
        #expect(try fixture.contents(of: replacement.mainURL) == "new-main")
    }

    @Test("Cancelling a stale writer cannot remove a replacement commit")
    func staleCancellationPreservesReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let old = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("old.mp3")
        )
        try fixture.stage("old-main", for: old)
        let replacement = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("new.mp3")
        )
        try fixture.stage("new-main", for: replacement)
        #expect(try fixture.ownership.commit(replacement))

        let staleCancellationOwnedCache = fixture.ownership.cancel(old)

        #expect(!staleCancellationOwnedCache)
        #expect(try fixture.contents(of: replacement.mainURL) == "new-main")
        #expect(try fixture.contents(of: replacement.sourceMetadataURL) == replacement.sourceURL.absoluteString)
    }

    @Test("Partial cleanup preserves active staging and removes abandoned staging")
    func cleanupPreservesActiveStaging() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let lease = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("active.mp3")
        )
        try fixture.stage("active-main", for: lease)
        let abandoned = lease.directory.appendingPathComponent("abandoned.mp3.partial")
        try Data("abandoned".utf8).write(to: abandoned)

        fixture.ownership.cleanupPartialFiles()

        #expect(fixture.fileManager.fileExists(atPath: lease.mainStagingURL.path))
        #expect(!fixture.fileManager.fileExists(atPath: abandoned.path))

        #expect(fixture.ownership.cancel(lease))
        let stale = lease.directory.appendingPathComponent("stale.mp3.partial")
        try Data("stale".utf8).write(to: stale)
        fixture.ownership.cleanupPartialFiles()
        #expect(!fixture.fileManager.fileExists(atPath: stale.path))

        let maintenanceSnapshot = try #require(
            fixture.ownership.beginMaintenance(songID: "maintenance")
        )
        let maintenanceDirectory = fixture.root.appendingPathComponent(
            "maintenance",
            isDirectory: true
        )
        try fixture.fileManager.createDirectory(
            at: maintenanceDirectory,
            withIntermediateDirectories: true
        )
        let maintenanceStaging = maintenanceDirectory.appendingPathComponent(
            "main-compress-active.nkz.staging"
        )
        let maintenanceTemporary = maintenanceStaging.appendingPathExtension("tmp")
        let maintenanceURLs = [maintenanceStaging, maintenanceTemporary]
        #expect(
            fixture.ownership.registerMaintenanceStaging(
                maintenanceURLs,
                for: maintenanceSnapshot
            )
        )
        for url in maintenanceURLs {
            try Data("active-maintenance".utf8).write(to: url)
        }
        fixture.ownership.cleanupPartialFiles()
        #expect(maintenanceURLs.allSatisfy { fixture.fileManager.fileExists(atPath: $0.path) })

        fixture.ownership.unregisterMaintenanceStaging(maintenanceURLs)
        fixture.ownership.cleanupPartialFiles()
        #expect(maintenanceURLs.allSatisfy { !fixture.fileManager.fileExists(atPath: $0.path) })
    }

    @Test("Stale compression cannot remove a newer main file")
    func staleCompressionCommitIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let initial = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("initial.mp3")
        )
        try fixture.stage("initial-main", for: initial)
        #expect(try fixture.ownership.commit(initial))
        let compressionSnapshot = try #require(
            fixture.ownership.beginMaintenance(songID: "song")
        )

        let replacement = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("replacement.mp3")
        )
        try fixture.stage("replacement-main", for: replacement)
        #expect(try fixture.ownership.commit(replacement))
        let compressed = replacement.mainURL.appendingPathExtension("nkz")

        let staleCompressionCommitted = try fixture.ownership.commitIfUnchanged(compressionSnapshot) {
            try fixture.fileManager.removeItem(at: replacement.mainURL)
            try Data("stale-compressed".utf8).write(to: compressed)
        }

        #expect(!staleCompressionCommitted)
        #expect(try fixture.contents(of: replacement.mainURL) == "replacement-main")
        #expect(!fixture.fileManager.fileExists(atPath: compressed.path))
    }

    @Test("Stale validation cannot delete a newer song directory")
    func staleValidationRemovalIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let initial = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("initial.mp3")
        )
        try fixture.stage("initial-main", for: initial)
        #expect(try fixture.ownership.commit(initial))
        let validationSnapshot = try #require(
            fixture.ownership.beginMaintenance(songID: "song")
        )

        let replacement = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("replacement.mp3")
        )
        try fixture.stage("replacement-main", for: replacement)
        #expect(try fixture.ownership.commit(replacement))

        let staleRemovalCommitted = try fixture.ownership.removeIfUnchanged(validationSnapshot) {
            try fixture.fileManager.removeItem(at: replacement.directory)
        }

        #expect(!staleRemovalCommitted)
        #expect(fixture.fileManager.fileExists(atPath: replacement.directory.path))
        #expect(try fixture.contents(of: replacement.mainURL) == "replacement-main")
        let retrySnapshot = try #require(
            fixture.ownership.beginMaintenance(songID: "song")
        )
        #expect(fixture.ownership.isCurrent(retrySnapshot))
    }

    @Test("Main audio and source metadata publish from the same lease")
    func mainAndSourceRemainPaired() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let stale = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("stale.mp3")
        )
        try fixture.stage("stale-main", for: stale)
        let winner = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("winner.mp3")
        )
        try fixture.stage("winner-main", for: winner)

        #expect(try fixture.ownership.commit(winner))
        let staleCommitted = try fixture.ownership.commit(stale)
        #expect(!staleCommitted)

        #expect(try fixture.contents(of: winner.mainURL) == "winner-main")
        #expect(try fixture.contents(of: winner.sourceMetadataURL) == winner.sourceURL.absoluteString)
    }

    @Test("Commit and cancellation are idempotent")
    func commitAndCancelAreIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let lease = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("once.mp3")
        )
        try fixture.stage("once-main", for: lease)

        let firstCommit = try fixture.ownership.commit(lease)
        let duplicateCommit = try fixture.ownership.commit(lease)
        let firstCancel = fixture.ownership.cancel(lease)
        let duplicateCancel = fixture.ownership.cancel(lease)

        #expect(firstCommit)
        #expect(!duplicateCommit)
        #expect(!firstCancel)
        #expect(!duplicateCancel)
        #expect(try fixture.contents(of: lease.mainURL) == "once-main")
    }

    @Test("Explicit cache clear revokes active writers")
    func clearRevokesActiveWriter() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let lease = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("late.mp3")
        )
        try fixture.stage("late-main", for: lease)

        fixture.ownership.invalidateAllAndRemove {
            if let entries = try? fixture.fileManager.contentsOfDirectory(
                at: fixture.root,
                includingPropertiesForKeys: nil
            ) {
                for entry in entries {
                    try? fixture.fileManager.removeItem(at: entry)
                }
            }
        }
        let lateCommit = try fixture.ownership.commit(lease)

        #expect(!lateCommit)
        #expect(!fixture.fileManager.fileExists(atPath: lease.mainURL.path))
        #expect(!fixture.fileManager.fileExists(atPath: lease.sourceMetadataURL.path))
    }

    @Test("Explicit song removal revokes an active writer")
    func songRemovalRejectsLateWriterCommit() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let lease = fixture.ownership.beginWrite(
            songID: "song",
            sourceURL: fixture.remoteURL("late.mp3")
        )
        try fixture.stage("late-main", for: lease)

        fixture.ownership.invalidateAndRemove(songID: "song") {
            try? fixture.fileManager.removeItem(at: lease.directory)
        }
        let lateCommit = try fixture.ownership.commit(lease)

        #expect(!lateCommit)
        #expect(!fixture.fileManager.fileExists(atPath: lease.mainURL.path))
        #expect(!fixture.fileManager.fileExists(atPath: lease.sourceMetadataURL.path))
    }

    private struct Fixture {
        let root: URL
        let ownership: AudioCacheMainOwnership
        let fileManager = FileManager.default

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(
                path: "AudioCacheMainOwnershipTests.\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            ownership = AudioCacheMainOwnership(rootDirectory: root)
        }

        func cleanup() {
            try? fileManager.removeItem(at: root)
        }

        func remoteURL(_ name: String) -> URL {
            URL(string: "https://example.com/\(name)")!
        }

        func stage(_ contents: String, for lease: AudioCacheMainOwnership.WriteLease) throws {
            try Data(contents.utf8).write(to: lease.mainStagingURL)
        }

        func contents(of url: URL) throws -> String {
            try String(contentsOf: url, encoding: .utf8)
        }
    }
}
