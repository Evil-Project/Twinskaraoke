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
        splash.next(expectedFingerprint: update.fingerprint, expectedIndex: 1)
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
        session.open(.init()) { advanced = true }
        defer { session.stop() }
        for _ in 0..<120 where session.loading && session.failure == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let page = try #require(session.page)
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
}
