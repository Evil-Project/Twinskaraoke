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
