import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

@Suite("Phone and watch playback protocol")
struct CompanionPlaybackTests {
    private let session = UUID()
    private let client = UUID()

    @Test("A newer position snapshot restores playback after reconnection")
    func reconnectPosition() {
        let first = snapshot(revision: 3, position: 12, at: Date(timeIntervalSince1970: 100))
        let later = snapshot(revision: 3, position: 32, at: Date(timeIntervalSince1970: 120))
        #expect(later.supersedes(first))
        #expect(!first.supersedes(later))
        #expect(CompanionPlayback.decode(
            CompanionPlayback.Snapshot.self,
            from: CompanionPlayback.encode(later)
        ) == later)
    }

    @Test("An old session cannot replace a newer phone session")
    func oldSession() {
        let current = snapshot(revision: 1, position: 0, at: Date(timeIntervalSince1970: 200))
        var old = snapshot(revision: 99, position: 90, at: Date(timeIntervalSince1970: 100))
        old.sessionID = UUID()
        #expect(!old.supersedes(current))
    }

    @Test("Only one owner is serialized for a playing session")
    func oneOwner() {
        let state = snapshot(revision: 4, position: 8, at: .now)
        #expect(state.isPlaying)
        #expect(state.owner == .phone)
        #expect(CompanionPlayback.decode(
            CompanionPlayback.Snapshot.self,
            from: CompanionPlayback.encode(state)
        )?.owner == .phone)
    }

    @Test("All repeat settings survive a phone-to-watch snapshot")
    func repeatSettings() {
        for setting in [CompanionPlayback.RepeatSetting.off, .one, .all] {
            var state = snapshot(revision: 1, position: 0, at: .now)
            state.repeatSetting = setting
            #expect(CompanionPlayback.decode(
                CompanionPlayback.Snapshot.self,
                from: CompanionPlayback.encode(state)
            )?.repeatSetting == setting)
        }
        #expect(PlaybackMode.off.next == .one)
        #expect(PlaybackMode.one.next == .all)
        #expect(PlaybackMode.all.next == .off)
    }

    @Test("Watch mirrors a new track and later position without opening audio")
    @MainActor
    func appliesPlaybackSnapshots() {
        let manager = AudioManager()
        var first = snapshot(revision: 1, position: 0, at: .now)
        first.queue = [first.song!]
        manager.applyCompanionSnapshot(first)
        #expect(manager.currentSong?.id == "song")
        #expect(manager.queue.count == 1)
        #expect(manager.isPlaying)
        #expect(manager.currentTime == 0)

        var next = first
        next.revision = 2
        next.song = UITestFixtures.song(id: "next", title: "Next", artist: "Artist")
        next.queue = [first.song!, next.song!]
        next.position = 12
        next.repeatSetting = .all
        next.isShuffled = true
        manager.applyCompanionSnapshot(next)
        #expect(manager.currentSong?.title == "Next")
        #expect(manager.currentIndex == 1)
        #expect(manager.currentTime == 12)
        #expect(manager.playbackMode == .all)
        #expect(manager.isShuffleOn)
    }

    @Test("Duplicate, reordered, and stale watch controls are rejected")
    func commandOrdering() {
        var gate = CompanionPlayback.CommandGate()
        let lastPhoneChange = Date(timeIntervalSince1970: 100)
        let first = command(sequence: 1, issuedAt: 110, baseRevision: 2)
        #expect(gate.decide(first, sessionID: session, revision: 2,
                            lastPhoneChangeAt: lastPhoneChange) == .accept)
        #expect(gate.decide(first, sessionID: session, revision: 2,
                            lastPhoneChangeAt: lastPhoneChange) == .duplicate)
        let third = command(sequence: 3, issuedAt: 111, baseRevision: 2)
        #expect(gate.decide(third, sessionID: session, revision: 2,
                            lastPhoneChangeAt: lastPhoneChange) == .accept)
        let delayedSecond = command(sequence: 2, issuedAt: 110.5, baseRevision: 2)
        #expect(gate.decide(delayedSecond, sessionID: session, revision: 2,
                            lastPhoneChangeAt: lastPhoneChange) == .stale)
        let oldPhoneState = command(sequence: 4, issuedAt: 115, baseRevision: 2)
        #expect(gate.decide(oldPhoneState, sessionID: session, revision: 3,
                            lastPhoneChangeAt: Date(timeIntervalSince1970: 120)) == .stale)
    }

    @Test("Ownership epochs reject delayed state after both handoff directions")
    func ownershipEpochs() {
        var lease = CompanionPlayback.Lease(sessionID: session)
        let phone = snapshot(revision: 500, position: 42, at: .now)
        #expect(lease.accepts(phone))
        lease.transfer(to: .watch)
        var watch = phone
        watch.owner = .watch
        watch.ownershipEpoch = lease.epoch
        watch.revision = 1
        #expect(lease.accepts(watch))
        #expect(!lease.accepts(phone))
        #expect(watch.supersedes(phone))
        lease.transfer(to: .phone)
        var returned = phone
        returned.ownershipEpoch = lease.epoch
        #expect(returned.supersedes(watch))
        #expect(!lease.accepts(watch))
        #expect(lease.accepts(returned))
    }

    @Test("The output grant survives relaunch without authorizing the former owner")
    func persistedOwnership() throws {
        let suite = "CompanionPlaybackTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var lease = CompanionPlayback.Lease(sessionID: session)
        lease.transfer(to: .watch)
        CompanionPlayback.saveLease(lease, defaults: defaults)
        #expect(CompanionPlayback.readLease(defaults: defaults) == lease)
        #expect(CompanionPlayback.readLease(defaults: defaults)?.owner == .watch)
        var otherSession = snapshot(revision: 999, position: 0, at: .now)
        otherSession.sessionID = UUID()
        otherSession.owner = .watch
        otherSession.ownershipEpoch = lease.epoch
        #expect(!lease.accepts(otherSession))
    }

    @Test("A watch-owned snapshot restores paused with its seek position")
    @MainActor
    func localRestoreDoesNotAutoplay() {
        let manager = AudioManager()
        var state = snapshot(revision: 9, position: 45, at: .now)
        state.owner = .watch
        manager.applyCompanionSnapshot(state)
        #expect(!manager.isPlaying)
        #expect(manager.currentTime == 45)
        #expect(manager.currentSong?.id == "song")
    }

    @Test("A lost handoff reply cannot reactivate a relinquished output")
    func relinquishedOutput() {
        var lease = CompanionPlayback.Lease(sessionID: session)
        lease.transfer(to: .watch)
        let relinquished = lease
        #expect(lease.allowsAudio(on: .watch))
        #expect(!lease.allowsAudio(on: .phone))
        #expect(!lease.allowsAudio(on: .watch, relinquished: relinquished))
        lease.transfer(to: .phone)
        #expect(lease.allowsAudio(on: .phone))
        lease.transfer(to: .watch)
        #expect(lease.allowsAudio(on: .watch, relinquished: relinquished))
    }

    @Test("Delayed commands from an old process cannot replace a restarted controller")
    func retiredController() {
        var gate = CompanionPlayback.CommandGate()
        let old = command(sequence: 1, issuedAt: 100, baseRevision: 1)
        #expect(gate.decide(old, sessionID: session, revision: 1, lastPhoneChangeAt: .distantPast) == .accept)
        var restarted = command(sequence: 1, issuedAt: 120, baseRevision: 1)
        restarted.clientID = UUID()
        #expect(gate.decide(restarted, sessionID: session, revision: 1, lastPhoneChangeAt: .distantPast) == .accept)
        let delayed = command(sequence: 2, issuedAt: 110, baseRevision: 1)
        #expect(gate.decide(delayed, sessionID: session, revision: 1, lastPhoneChangeAt: .distantPast) == .stale)
    }

    private func snapshot(revision: Int, position: Double, at date: Date) -> CompanionPlayback.Snapshot {
        CompanionPlayback.Snapshot(
            sessionID: session, revision: revision, owner: .phone,
            song: UITestFixtures.song(id: "song", title: "Song", artist: "Artist"),
            queue: [], isPlaying: true, isRadio: false, radioArtworkURL: nil,
            position: position, duration: 180, isShuffled: false, repeatSetting: .off,
            error: nil, updatedAt: date
        )
    }

    private func command(sequence: Int, issuedAt: TimeInterval,
                         baseRevision: Int) -> CompanionPlayback.Command {
        CompanionPlayback.Command(
            sessionID: session, clientID: client, sequence: sequence,
            baseRevision: baseRevision, issuedAt: Date(timeIntervalSince1970: issuedAt),
            action: .next, song: nil, queue: nil, position: nil,
            streamURL: nil, artworkURL: nil
        )
    }
}
