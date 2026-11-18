import Foundation
import SwiftUI
import Testing
import WebKit
@testable import Twinskaraoke

@MainActor @Suite("Update splash") struct SplashUpdateTests {
    private func announcement() -> SplashContent {
        var content = SplashContent.placeholder(.update)
        content.enabled = true
        content.targetVersion = "2.0"
        return content
    }

    private func coordinator(_ store: MemorySplashStore, update: SplashContent) -> SplashCoordinator {
        SplashCoordinator(store: store, install: .placeholder(.install), update: update, version: "2.0", build: "42")
    }

    @Test func changelogAloneCompletesAnAnnouncementOnce() {
        var update = announcement()
        update.slides = Array(update.slides.prefix(1))
        let store = MemorySplashStore()
        store.value.installCompleted = true
        let splash = coordinator(store, update: update)
        splash.foreground()
        #expect(splash.active?.slides.first?.releaseNotes != nil)
        splash.complete(expectedFingerprint: update.fingerprint, expectedIndex: 0)
        #expect(store.value.completedUpdateIDs == [update.id] && !splash.isBlocking)
        let reopened = coordinator(store, update: update)
        reopened.foreground()
        #expect(!reopened.isBlocking)
    }

    @Test func studioReservesFirstPageAndPreservesLegacySlides() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = SplashStudioModel(kind: .update, directory: directory)
        var legacy = announcement()
        legacy.slides[0].releaseNotes = nil
        try studio.importData(legacy.encoded())
        #expect(Array(studio.draft.slides.dropFirst()) == legacy.slides)
        #expect(throws: SplashError.self) { try studio.draft.validateForPresentation() }
        #expect(throws: SplashError.self) { try SplashJSONDocument(content: studio.draft) }

        let notes = studio.draft.slides[0]
        studio.move(IndexSet(integer: 1), to: 0)
        studio.move(IndexSet(integer: 0), to: 2)
        studio.duplicate(0)
        studio.delete(IndexSet(integer: 0))
        #expect(studio.draft.slides == [notes] + legacy.slides)
        studio.draft.slides[0].releaseNotes?.general = [.init(headline: "Shared improvement")]
        studio.draft.slides[1].website = .init(url: "https://survey.example.org/form")
        #expect(throws: SplashError.self) { try SplashJSONDocument(content: studio.draft) }
        studio.draft.targetBuild = "42"
        let exported = try SplashJSONDocument(content: studio.draft)
        #expect(try SplashContent.decode(exported.data) == studio.draft)
        #expect(!studio.draft.eligible(version: "2.0", build: "43"))

        let last = studio.draft.slides[2]
        let binding = studio.binding(for: last)
        studio.delete(IndexSet(integer: 2))
        #expect(binding.wrappedValue == last)
        binding.wrappedValue.title = "Deleted"
        #expect(studio.draft.slides.count == 2)
    }

    @Test func excessiveDetailLinesAreRejectedAndLegacyRenderingIsBounded() throws {
        let entry = SplashReleaseNotes.Entry(headline: "Improvement", details: String(repeating: "x\n", count: 5000))
        #expect(entry.detailLines.count <= 30)
        var notes = SplashReleaseNotes()
        notes.general = [entry]
        #expect(throws: SplashError.self) { try notes.validateForPresentation() }
        notes.general[0].details = Array(repeating: "Detail", count: 30).joined(separator: "\n")
        try notes.validateForPresentation()
        #expect(notes.general[0].detailLines.count == 30)
        notes.general[0].details += "\nOne too many"
        #expect(throws: SplashError.self) { try notes.validateForPresentation() }
    }

    @Test func collidingSlideIDCannotRedirectRetainedBindingWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = SplashStudioModel(kind: .install, directory: directory)
        studio.draft = SplashContent(kind: .install, id: "binding-fixture", slides: [
            SplashSlide(id: "first-slide"), SplashSlide(id: "second-slide"),
        ])
        let original = studio.draft
        let first = original.slides[0]
        let second = original.slides[1]
        let binding = studio.binding(for: second)
        binding.wrappedValue.id = first.id
        #expect(studio.draft == original)
        #expect(binding.wrappedValue.id == second.id)
        binding.wrappedValue.id = "renamed-slide"
        binding.wrappedValue.title = "Edited second slide"
        #expect(studio.draft.slides[0] == first)
        #expect(studio.draft.slides[1].id == "renamed-slide")
        #expect(studio.draft.slides[1].title == "Edited second slide")
        studio.delete(IndexSet(integer: 1))
        let afterDeletion = studio.draft
        binding.wrappedValue.title = "Deleted slide edit"
        #expect(studio.draft == afterDeletion)
    }

    @Test func websiteHandshakeAcceptsOnlyItsCurrentOriginAndIDOnce() throws {
        let url = try #require(SplashWebsite(url: "https://survey.example.org/form?language=en").httpsURL)
        var session = try #require(SplashWebsiteHandshake(url: url))
        let replacement = try #require(SplashWebsiteHandshake(url: url))
        #expect(session.requestURL.fragment == "splashSession=\(session.id)")
        #expect(session.requestURL.query() == "language=en")
        let stale = session.consume(type: "completed", id: replacement.id, isMainFrame: true, origin: session.origin)
        #expect(!stale)
        let subframe = session.consume(type: "completed", id: session.id, isMainFrame: false, origin: session.origin)
        #expect(!subframe)
        let wrongType = session.consume(type: "finished", id: session.id, isMainFrame: true, origin: session.origin)
        #expect(!wrongType)
        let otherPort = SplashWebsiteHandshake.Origin(scheme: "https", host: "survey.example.org", port: 444)
        let wrongPort = session.consume(type: "completed", id: session.id, isMainFrame: true, origin: otherPort)
        #expect(!wrongPort)
        let accepted = session.consume(type: "completed", id: session.id, isMainFrame: true, origin: session.origin)
        #expect(accepted)
        let duplicate = session.consume(type: "completed", id: session.id, isMainFrame: true, origin: session.origin)
        #expect(!duplicate)
        #expect(SplashWebsite(url: "http://survey.example.org").httpsURL == nil)
        #expect(SplashWebsite(url: "https://user@survey.example.org").httpsURL == nil)
        #expect(SplashWebsite(url: "https://survey.example.org#already-set").httpsURL == nil)
    }

    @Test func websiteProgressUsesExistingSaveRetryAndResume() {
        var update = announcement()
        update.slides[1].website = .init(url: "https://survey.example.org/form")
        update.targetBuild = "42"
        update.slides.append(SplashSlide())
        let store = MemorySplashStore()
        store.value.installCompleted = true
        let splash = coordinator(store, update: update)
        splash.foreground()
        splash.next()

        store.failWrite = true
        splash.websiteAction(.completed, expectedFingerprint: update.fingerprint, expectedIndex: 1)
        #expect(splash.index == 1 && splash.errorMessage != nil)
        #expect(!splash.hasPassedCurrentSlide && store.value.pending?.index == 1)
        store.failWrite = false
        splash.retry()
        #expect(splash.index == 2 && store.value.pending?.index == 2)
        splash.back()
        #expect(splash.hasPassedCurrentSlide)

        let reopened = coordinator(store, update: update)
        reopened.foreground()
        #expect(reopened.index == 1 && reopened.hasPassedCurrentSlide)
        reopened.next()
        reopened.complete()
        #expect(!reopened.isBlocking && store.value.completedUpdateIDs == [update.id])
    }

    @Test func localWebsiteReportsCompletionFromWebKit() async throws {
        let session = SplashWebsiteSession()
        var advanced = false
        let owner = UUID()
        session.open(.init(), owner: owner) { if $0 == .completed { advanced = true } }
        defer { session.stop(owner: owner) }
        for _ in 0..<120 where session.loading && session.failure == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let page = try #require(session.page)
        let overscroll = try await page.callJavaScript("return document.documentElement.style.overscrollBehavior;") as? String
        #expect(overscroll == "none")
        let previousInteractions = session.interactionCount
        _ = try await page.callJavaScript("document.getElementById('feedback').click()")
        for _ in 0..<20 where session.interactionCount == previousInteractions {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.interactionCount == previousInteractions + 1)
        let hasID = try await page.callJavaScript("return typeof id === 'string';") as? Bool
        let hasBridge = try await page.callJavaScript("return !!window.webkit?.messageHandlers?.splashCompletion;") as? Bool
        #expect(hasID == true)
        #expect(hasBridge == true)
        _ = try await page.callJavaScript("document.getElementById('complete').click()")
        for _ in 0..<20 where !advanced {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(advanced)
    }

    private func websiteAnnouncement(count: Int = 1) -> SplashContent {
        var update = announcement()
        update.targetBuild = "42"
        update.slides = [update.slides[0]] + (0..<count).map { number in
            var slide = SplashSlide()
            slide.id = "website-\(number)"
            slide.website = .init(url: "https://survey.example.org/form\(number)")
            return slide
        } + [SplashSlide()]
        return update
    }

    private func send(_ action: SplashWebsiteAction, to splash: SplashCoordinator, update: SplashContent) {
        splash.websiteAction(action, expectedFingerprint: update.fingerprint, expectedIndex: splash.index)
    }

    @Test func deferredWebsiteReopensAloneAndCancellationStopsReminders() {
        let update = websiteAnnouncement()
        let store = MemorySplashStore(); store.value.installCompleted = true
        let splash = coordinator(store, update: update)
        splash.foreground(); splash.next()
        #expect(store.value.websites?.first?.status == .pending)
        send(.deferred, to: splash, update: update)
        #expect(splash.index == 2)
        splash.complete()
        #expect(!splash.isBlocking && !store.value.completedUpdateIDs.contains(update.id))
        splash.foreground() // Repeated active/protected-data notifications do not reopen it.
        #expect(!splash.isBlocking)
        splash.background(); splash.foreground()
        #expect(splash.isWebsiteOnly && splash.index == 1)
        send(.deferred, to: splash, update: update)
        #expect(!splash.isBlocking && store.value.websites?.first?.status == .pending)
        let reopened = coordinator(store, update: update)
        reopened.foreground()
        #expect(reopened.isWebsiteOnly && reopened.index == 1)
        send(.canceled, to: reopened, update: update)
        #expect(!reopened.isBlocking && store.value.completedUpdateIDs.contains(update.id))
        reopened.background(); reopened.foreground()
        #expect(!reopened.isBlocking && store.value.websites?.first?.status == .canceled)
    }

    @Test func eachTerminalOutcomeResolvesOnlyItsOwnSlide() {
        let update = websiteAnnouncement(count: 3)
        let store = MemorySplashStore(); store.value.installCompleted = true
        let splash = coordinator(store, update: update)
        splash.foreground(); splash.next()
        for _ in 0..<3 { send(.deferred, to: splash, update: update) }
        splash.complete()
        let reopened = coordinator(store, update: update)
        reopened.foreground()
        #expect(reopened.isWebsiteOnly && reopened.index == 1)
        send(.completed, to: reopened, update: update)
        #expect(reopened.index == 2 && store.value.websites?.map(\.status) == [.completed, .pending, .pending])
        #expect(!store.value.completedUpdateIDs.contains(update.id))
        send(.canceled, to: reopened, update: update)
        #expect(reopened.index == 3 && store.value.websites?.map(\.status) == [.completed, .canceled, .pending])
        #expect(!store.value.completedUpdateIDs.contains(update.id))
        send(.closed, to: reopened, update: update)
        #expect(reopened.isBlocking && reopened.currentWebsiteStatus == .closed)
        #expect(store.value.completedUpdateIDs.contains(update.id))
        send(.deferred, to: reopened, update: update) // Native Continue after HTTP 410.
        #expect(!reopened.isBlocking && store.value.completedUpdateIDs.contains(update.id))
    }

    @Test func interruptedFirstWebsiteReturnsWithoutReplayingNativeSlides() {
        let update = websiteAnnouncement()
        let store = MemorySplashStore(); store.value.installCompleted = true
        let splash = coordinator(store, update: update)
        splash.foreground(); splash.next()
        splash.background(); splash.foreground()
        #expect(splash.isWebsiteOnly && splash.index == 1)
        send(.completed, to: splash, update: update)
        #expect(!splash.isBlocking && store.value.completedUpdateIDs.contains(update.id))
    }

    @Test func reminderSaveFailureRetriesItsOutcomeWithoutAnotherCallback() {
        let update = websiteAnnouncement(count: 2)
        let store = MemorySplashStore(); store.value.installCompleted = true
        let splash = coordinator(store, update: update)
        splash.foreground(); splash.next()
        send(.deferred, to: splash, update: update)
        let reopened = coordinator(store, update: update); reopened.foreground()
        store.failWrite = true
        send(.completed, to: reopened, update: update)
        #expect(reopened.index == 1 && reopened.errorMessage != nil)
        #expect(store.value.websites?.map(\.status) == [.pending, .pending])
        store.failWrite = false; reopened.retry()
        #expect(reopened.index == 2 && store.value.websites?.map(\.status) == [.completed, .pending])
        reopened.websiteAction(.canceled, expectedFingerprint: update.fingerprint, expectedIndex: 1)
        #expect(reopened.index == 2 && store.value.websites?.last?.status == .pending)
        send(.completed, to: reopened, update: update)
        #expect(store.value.completedUpdateIDs.contains(update.id) && !reopened.isBlocking)
    }

    @Test func retiredFormsDoNotReopenAndOldStateStillDecodes() throws {
        let oldJSON = Data("{\"schemaVersion\":1,\"installCompleted\":true,\"completedUpdateIDs\":[\"older\"]}".utf8)
        let decoded = try JSONDecoder().decode(SplashState.self, from: oldJSON)
        #expect(decoded.websites == nil && decoded.completedUpdateIDs == ["older"])
        let update = websiteAnnouncement()
        let store = MemorySplashStore(); store.value.installCompleted = true
        let splash = coordinator(store, update: update); splash.foreground(); splash.next()
        var disabled = update; disabled.enabled = false
        let reopened = coordinator(store, update: disabled); reopened.foreground()
        #expect(!reopened.isBlocking && store.value.websites?.isEmpty == true)
        let wrongBuild = SplashCoordinator(store: store, install: .placeholder(.install), update: update, version: "2.0", build: "43")
        wrongBuild.foreground()
        #expect(!wrongBuild.isBlocking)
    }

    @Test func cancellationHandshakeIsTerminalAndCannotBeReused() throws {
        let url = try #require(URL(string: "https://survey.example.org/form"))
        var handshake = try #require(SplashWebsiteHandshake(url: url))
        let canceled = handshake.consume(type: "canceled", id: handshake.id, isMainFrame: true, origin: handshake.origin)
        let duplicate = handshake.consume(type: "completed", id: handshake.id, isMainFrame: true, origin: handshake.origin)
        #expect(canceled && !duplicate)
    }

    @Test func nativeRecoveryWorksAfterThePageReportsASubmissionFailure() async throws {
        let session = SplashWebsiteSession(); let owner = UUID()
        var actions: [SplashWebsiteAction] = []
        session.open(.init(), owner: owner) { actions.append($0) }
        defer { session.stop(owner: owner) }
        for _ in 0..<120 where session.loading && session.failure == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let page = try #require(session.page)
        let originalID = try await page.callJavaScript("return id;") as? String
        _ = try await page.callJavaScript("document.getElementById('feedback').value = 'Draft'; document.getElementById('fail').click();")
        #expect(actions.isEmpty && session.failure == nil && !session.loading)
        session.open(.init(), owner: owner) { actions.append($0) }
        for _ in 0..<120 where session.loading && session.failure == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let replacement = try #require(session.page)
        let newID = try await replacement.callJavaScript("return id;") as? String
        #expect(originalID != nil && newID != nil && originalID != newID)
        session.continueForNow(owner: owner)
        session.continueForNow(owner: owner)
        #expect(actions == [.deferred] && session.page == nil)
    }

    @Test func finalWebsiteUsesDoneButDeferralDoesNotCompleteAnnouncement() {
        var update = websiteAnnouncement()
        update.slides.removeLast()
        for outcome in [SplashWebsiteAction.completed, .canceled, .deferred] {
            let store = MemorySplashStore(); store.value.installCompleted = true
            let splash = coordinator(store, update: update); splash.foreground(); splash.next()
            send(outcome, to: splash, update: update)
            #expect(!splash.isBlocking && store.value.pending == nil)
            #expect(store.value.completedUpdateIDs.contains(update.id) == (outcome != .deferred))
            #expect(store.value.websites?.first?.status == (outcome == .deferred ? .pending : .init(rawValue: outcome.rawValue)))
        }
    }

    @Test func anActiveSessionHasOnlyOneWindowOwner() async throws {
        let session = SplashWebsiteSession(); let owner = UUID(); let other = UUID()
        var actions: [SplashWebsiteAction] = []
        session.open(.init(), owner: owner) { actions.append($0) }
        defer { session.stop(owner: owner) }
        let page = session.page
        session.open(.init(), owner: other) { actions.append($0) }
        session.continueForNow(owner: other); session.stop(owner: other)
        #expect(session.owner == owner && session.page === page && actions.isEmpty)
        for _ in 0..<120 where session.loading && session.failure == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let activePage = try #require(session.page)
        _ = try await activePage.callJavaScript("document.getElementById('cancel').click()")
        for _ in 0..<20 where actions.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        session.continueForNow(owner: owner)
        #expect(actions == [.canceled] && session.page == nil)
    }

    @Test func reminderPresentationSaveFailureKeepsNativeRetryVisible() {
        let update = websiteAnnouncement()
        let store = MemorySplashStore(); store.value.installCompleted = true
        let splash = coordinator(store, update: update); splash.foreground(); splash.next()
        send(.deferred, to: splash, update: update); splash.complete()
        store.failWrite = true; splash.background(); splash.foreground()
        #expect(splash.isBlocking && splash.active == nil && splash.errorMessage != nil)
        store.failWrite = false; splash.retry()
        #expect(splash.isWebsiteOnly && splash.index == 1 && splash.errorMessage == nil)
    }

    @Test func httpGoneIsTerminalAndTemporaryFailuresRemainRetryable() throws {
        let url = try #require(URL(string: "https://survey.example.org/form"))
        for (status, expected) in [(200, nil), (410, SplashWebsiteSession.Failure.closed), (503, .unavailable)] {
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            #expect(SplashWebsiteSession.failure(for: response, canShowMimeType: true) == expected)
        }
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        #expect(SplashWebsiteSession.failure(for: response, canShowMimeType: false) == .unavailable)
    }

    @Test func pendingFormsRetireWhenBuildOrFingerprintChangesAndInstallStaysFirst() {
        let update = websiteAnnouncement()
        let store = MemorySplashStore(); store.value.installCompleted = true
        let splash = coordinator(store, update: update); splash.foreground(); splash.next()
        let saved = store.value
        let wrongBuild = SplashCoordinator(store: store, install: .placeholder(.install), update: update, version: "2.0", build: "43")
        wrongBuild.foreground()
        #expect(!wrongBuild.isBlocking && store.value.websites?.isEmpty == true)
        store.value = saved
        var edited = update; edited.slides[1].website?.url = "https://survey.example.org/replacement"
        let changed = coordinator(store, update: edited); changed.foreground()
        #expect(!changed.isWebsiteOnly && changed.index == 0 && store.value.websites?.isEmpty == true)
        store.value = saved; store.value.installCompleted = false
        let installFirst = coordinator(store, update: update); installFirst.foreground()
        #expect(installFirst.active?.kind == .install && !installFirst.isWebsiteOnly)
    }

    @Test(arguments: ["\n", "\r", "\r\n", "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}"])
    func everyNewlineSeparatesBoundedDetailRows(_ separator: String) {
        let entry = SplashReleaseNotes.Entry(headline: "Improvement", details: " One \(separator) \(separator) Two ")
        #expect(entry.detailLines == ["One", "Two"])
        let overLimit = SplashReleaseNotes.Entry(headline: "Improvement", details: Array(repeating: "Detail", count: 31).joined(separator: separator))
        #expect(overLimit.detailLines.count == 30)
        #expect(overLimit.hasTooManyDetailLines)
    }

    @Test func oversizedLegacyDraftRemainsEditableUntilReadyForPresentation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var legacy = announcement()
        let details = Array(repeating: "Detail", count: 31).joined(separator: "\n")
        legacy.slides[0].releaseNotes?.general = [.init(headline: "Improvement", details: details)]
        let studio = SplashStudioModel(kind: .update, directory: directory)
        try studio.importData(JSONEncoder().encode(legacy))
        #expect(studio.draft == legacy)
        #expect(studio.saveDraft(announce: false))
        let reopened = SplashStudioModel(kind: .update, directory: directory)
        #expect(reopened.draft == legacy)
        #expect(throws: SplashError.self) { try reopened.draft.validateForPresentation() }
        #expect(throws: SplashError.self) { try SplashJSONDocument(content: reopened.draft) }
        reopened.draft.slides[0].releaseNotes?.general[0].details = "Shortened detail"
        try reopened.draft.validateForPresentation()
        _ = try SplashJSONDocument(content: reopened.draft)
    }
}
