import Foundation
import SwiftUI
import Testing
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
        let exported = try SplashJSONDocument(content: studio.draft)
        #expect(try SplashContent.decode(exported.data) == studio.draft)

        let last = studio.draft.slides[2]
        let binding = studio.binding(for: last)
        studio.delete(IndexSet(integer: 2))
        #expect(binding.wrappedValue == last)
        binding.wrappedValue.title = "Deleted"
        #expect(studio.draft.slides.count == 2)
    }
}
