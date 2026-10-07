import Foundation
import Testing
import UIKit
@testable import Twinskaraoke

@MainActor private final class MemorySplashStore: SplashStateStoring {
    var value = SplashState()
    var failRead = false
    var failWrite = false
    var saves = 0
    func read() throws -> SplashState {
        if failRead { throw SplashError(message: "Protected data unavailable") }
        return value
    }
    func save(_ state: SplashState) throws {
        if failWrite { throw SplashError(message: "Disk full") }
        value = state; saves += 1
    }
}

@MainActor @Suite("Splash experience") struct SplashExperienceTests {
    private func coordinator(_ store: MemorySplashStore, install: SplashContent = .placeholder(.install), update: SplashContent? = nil) -> SplashCoordinator {
        SplashCoordinator(store: store, install: install, update: update, version: "2.0", build: "42")
    }
    private func finish(_ coordinator: SplashCoordinator) {
        guard let active = coordinator.active else { return }
        for _ in 1..<active.slides.count { coordinator.next() }
        coordinator.complete()
    }
    private func announcement(_ id: String = "release-two") -> SplashContent {
        var content = SplashContent.placeholder(.update)
        content.enabled = true; content.targetVersion = "2.0"; content.id = id
        return content
    }

    @Test func missingStateCoversFreshInstallAndExistingRollout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SplashStateStore(directory: directory)
        #expect(try store.read() == SplashState())
        let c = SplashCoordinator(store: store, install: .placeholder(.install), update: nil)
        c.foreground()
        #expect(c.active?.kind == .install)
        #expect(c.index == 0 && c.isBlocking)
        #expect(try store.read().pending?.index == 0)
    }
    @Test func installCompletionDoesNotReplayAcrossRestartsOrContentChanges() {
        let store = MemorySplashStore(); let c = coordinator(store); c.foreground(); finish(c)
        #expect(store.value.installCompleted && !c.isBlocking)
        var changed = SplashContent.placeholder(.install); changed.id = "new-content"; changed.slides.append(SplashSlide())
        let restarted = coordinator(store, install: changed); restarted.foreground()
        #expect(!restarted.isBlocking && restarted.active == nil)
    }
    @Test func interruptedProgressRecoversAndBackDoesNotForgetSequence() {
        let store = MemorySplashStore(); let c = coordinator(store); c.foreground(); c.next(); c.next(); c.back()
        #expect(!store.value.installCompleted)
        let resumed = coordinator(store); resumed.foreground()
        #expect(resumed.index == 1 && store.value.pending?.highestVisited == 2)
        resumed.complete(); #expect(!store.value.installCompleted)
        resumed.next(); resumed.complete(); #expect(store.value.installCompleted)
    }
    @Test func prematureCompletionAndBoundaryNavigationAreRejected() {
        let store = MemorySplashStore(); let c = coordinator(store); c.foreground()
        c.back(); c.complete()
        #expect(c.index == 0 && !store.value.installCompleted)
        c.next(); c.complete(); #expect(!store.value.installCompleted)
        c.next(); c.next(); #expect(c.index == 2)
        c.complete(); let count = store.saves; c.complete(); c.foreground()
        #expect(store.saves == count && !c.isBlocking)
    }
    @Test func singleSlideRequiresOnlyFinalButton() {
        var content = SplashContent.placeholder(.install); content.slides = [content.slides[0]]
        let store = MemorySplashStore(); let c = coordinator(store, install: content); c.foreground()
        #expect(c.isBlocking); c.next(); #expect(c.index == 0); c.complete(); #expect(!c.isBlocking)
    }
    @Test func changedUnfinishedContentRestartsSafely() {
        let store = MemorySplashStore(); let c = coordinator(store); c.foreground(); c.next(); c.next()
        var content = SplashContent.placeholder(.install); content.slides.insert(SplashSlide(), at: 0)
        let changed = coordinator(store, install: content); changed.foreground()
        #expect(changed.index == 0 && store.value.pending?.highestVisited == 0)
        changed.complete(); #expect(!store.value.installCompleted)
    }
    @Test func malformedSavedSlideIndexCannotBypassSlides() {
        let store = MemorySplashStore(); let content = SplashContent.placeholder(.install)
        store.value.pending = SplashProgress(kind: .install, id: content.id, fingerprint: content.fingerprint, index: 20, highestVisited: 20)
        let c = coordinator(store); c.foreground()
        #expect(c.index == 0 && store.value.pending?.highestVisited == 0)
    }
    @Test func releaseEligibilityMatchesExactVersionAndOptionalBuild() {
        var content = announcement()
        #expect(content.eligible(version: "2.0", build: "1"))
        #expect(!content.eligible(version: "2.0.0", build: "1"))
        content.targetBuild = "42"
        #expect(content.eligible(version: "2.0", build: "42"))
        #expect(!content.eligible(version: "2.0", build: "43"))
        content.enabled = false
        #expect(!content.eligible(version: "2.0", build: "42"))
    }
    @Test func absentDisabledAndMismatchedAnnouncementsShowNothing() {
        for content in [nil, SplashContent.placeholder(.update), { var c = announcement(); c.targetVersion = "1.9"; return c }(), { var c = announcement(); c.targetBuild = "43"; return c }()] {
            let store = MemorySplashStore(); store.value.installCompleted = true
            let c = coordinator(store, update: content); c.foreground()
            #expect(!c.isBlocking && store.value.completedUpdateIDs.isEmpty)
        }
    }
    @Test func installPrecedesUpdateAndNoInterfaceUnlocksBetweenThem() {
        let store = MemorySplashStore(); let c = coordinator(store, update: announcement()); c.foreground()
        #expect(c.active?.kind == .install)
        finish(c)
        #expect(c.isBlocking && c.active?.kind == .update && store.value.installCompleted)
        finish(c)
        #expect(!c.isBlocking && store.value.completedUpdateIDs == ["release-two"])
    }
    @Test func announcementIdentitySurvivesContentEditsAndBuildsAndDowngrades() {
        let store = MemorySplashStore(); store.value.installCompleted = true
        let c = coordinator(store, update: announcement()); c.foreground(); finish(c)
        var edited = announcement(); edited.slides.append(SplashSlide())
        let reused = coordinator(store, update: edited); reused.foreground(); #expect(!reused.isBlocking)
        let downgraded = SplashCoordinator(store: store, install: .placeholder(.install), update: edited, version: "1.0", build: "1")
        downgraded.foreground(); #expect(store.value.completedUpdateIDs.contains(edited.id))
        let new = coordinator(store, update: announcement("new-id")); new.foreground(); #expect(new.active?.id == "new-id")
    }
    @Test func readFailureBlocksAndRetryRestoresOriginalState() {
        let store = MemorySplashStore(); store.value.installCompleted = true; store.failRead = true
        let c = coordinator(store); c.foreground()
        #expect(c.isBlocking && c.active == nil && c.errorMessage != nil && store.saves == 0)
        store.failRead = false; c.foreground()
        #expect(!c.isBlocking && store.value.installCompleted)
    }
    @Test func progressionWriteFailureDoesNotAdvanceAndRetryPersists() {
        let store = MemorySplashStore(); let c = coordinator(store); c.foreground()
        store.failWrite = true; c.next()
        #expect(c.index == 0 && c.errorMessage != nil && store.value.pending?.index == 0)
        c.next(); #expect(c.index == 0)
        store.failWrite = false; c.retry()
        #expect(c.index == 1 && store.value.pending?.index == 1)
    }
    @Test func completionWriteFailureNeverUnlocks() {
        let store = MemorySplashStore(); let c = coordinator(store); c.foreground(); c.next(); c.next()
        store.failWrite = true; c.complete()
        #expect(c.isBlocking && !store.value.installCompleted && c.errorMessage != nil)
        store.failWrite = false; c.retry()
        #expect(!c.isBlocking && store.value.installCompleted)
    }
    @Test func realStoreAtomicRoundTripAndBackupExclusion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SplashStateStore(directory: directory)
        var state = SplashState(); state.installCompleted = true; state.completedUpdateIDs = ["a", "b"]
        try store.save(state); #expect(try store.read() == state)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try store.file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        state.completedUpdateIDs.insert("c"); try store.save(state)
        #expect(try store.read() == state)
        #expect(try store.file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
    @Test func corruptFutureAndUnavailableStateAreNotFreshInstall() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SplashStateStore(directory: directory)
        try Data("{bad}".utf8).write(to: store.file)
        #expect(throws: (any Error).self) { try store.read() }
        var state = SplashState(); state.schemaVersion = 2
        try JSONEncoder().encode(state).write(to: store.file)
        #expect(throws: (any Error).self) { try store.read() }
        try FileManager.default.removeItem(at: store.file)
        try FileManager.default.createDirectory(at: store.file, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try store.read() }
        #expect(throws: (any Error).self) { try store.save(SplashState()) }
    }
    @Test func malformedMandatoryContentFallsBackAndOptionalContentSkips() {
        var install = SplashContent.placeholder(.install); install.slides = []
        var update = announcement(); update.schemaVersion = 999
        let store = MemorySplashStore(); let c = coordinator(store, install: install, update: update); c.foreground()
        #expect(c.active?.slides.count == 3); finish(c)
        #expect(!c.isBlocking && store.value.completedUpdateIDs.isEmpty)
    }
    @Test func validationRejectsInvalidDesignAndSize() throws {
        var c = SplashContent.placeholder(.install); c.slides[1].id = c.slides[0].id
        #expect(throws: SplashError.self) { try c.encoded() }
        c = .placeholder(.install); c.slides[0].backgroundColor = "red"
        #expect(throws: SplashError.self) { try c.encoded() }
        c = .placeholder(.install); c.slides[0].symbol = "not-a-real-sf-symbol"
        #expect(throws: SplashError.self) { try c.encoded() }
        c = .placeholder(.install); c.slides[0].symbol = nil; c.slides[0].imageData = Data("invalid-image".utf8)
        #expect(throws: SplashError.self) { try c.encoded() }
        c.slides[0].imageData = Data(repeating: 0, count: SplashContent.maxImageBytes + 1)
        #expect(throws: SplashError.self) { try c.encoded() }
        #expect(throws: SplashError.self) { try SplashContent.decode(Data(repeating: 0, count: SplashContent.maxFileBytes + 1)) }
        let data = try SplashContent.placeholder(.install).encoded()
        let unknownLayout = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "imageAbove", with: "absolute")
        #expect(throws: SplashError.self) { try SplashContent.decode(Data(unknownLayout.utf8)) }
        #expect(throws: SplashError.self) { try SplashContent.decode(data, expectedKind: .update) }
    }
    @Test func exportImportRoundTripIncludesEmbeddedImage() throws {
        var c = announcement()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16))
        let image = renderer.image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 16)) }
        c.slides[0].imageData = image.pngData(); c.slides[0].symbol = nil
        #expect(c.slides[0].imageData != nil)
        let bytes = try c.encoded(); let decoded = try SplashContent.decode(bytes)
        #expect(decoded == c && decoded.slides[0].imageData == c.slides[0].imageData)
        #expect(decoded.fingerprint == c.fingerprint)
    }
    @Test func studioPreviewDraftAndExportNeverTouchCompletionState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SplashStateStore(directory: directory)
        var state = SplashState(); state.installCompleted = true; state.completedUpdateIDs = ["old"]
        try store.save(state)
        let studio = SplashStudioModel(directory: directory.appendingPathComponent("Drafts"))
        let oldID = studio.draft.id; studio.draft.slides[0].title = "Edited"; studio.duplicate(0)
        #expect(studio.draft.id == oldID && studio.draft.slides.count == 4)
        #expect(studio.saveDraft())
        let document = try SplashJSONDocument(content: studio.draft)
        try studio.importData(document.data)
        _ = SplashPreviewView(content: studio.draft)
        #expect(try store.read() == state)
        studio.switchMode(.update); let id = studio.draft.id; studio.draft.slides[0].body = "Edit"
        #expect(studio.draft.id == id); studio.newAnnouncement(); #expect(studio.draft.id != id)
    }
    @Test func staleSceneActionsCannotAdvanceOrCompleteTheNextExperience() {
        let store = MemorySplashStore()
        var update = announcement(); update.slides = [update.slides[0]]
        let c = coordinator(store, update: update); c.foreground()
        let fingerprint = c.active!.fingerprint
        c.next(expectedFingerprint: fingerprint, expectedIndex: 0)
        c.next(expectedFingerprint: fingerprint, expectedIndex: 0)
        #expect(c.index == 1)
        c.next(); c.complete(expectedFingerprint: fingerprint, expectedIndex: 2)
        #expect(c.active?.kind == .update)
        c.complete(expectedFingerprint: fingerprint, expectedIndex: 2)
        #expect(c.isBlocking && store.value.completedUpdateIDs.isEmpty)
        c.complete(); #expect(!c.isBlocking)
    }
    @Test func incomingRoutesAreDeferredAndDetailsArePreservedInOrder() throws {
        var blocked = true
        let router = AppRouter(isSplashBlocking: { blocked })
        router.open(try #require(AppRoute(url: URL(string: "twinskaraoke://search")!)))
        router.open(.playlist("first")); router.open(.playlist("second")); router.open(.radio)
        #expect(router.section == .home && router.detail == nil)
        blocked = false; router.resumeAfterSplash()
        #expect(router.detail == .playlist("first"))
        router.dismissDetail(); router.resumeAfterSplash()
        #expect(router.detail == .playlist("second"))
        router.dismissDetail(); router.resumeAfterSplash()
        #expect(router.section == .radio && router.detail == nil)
    }
    @Test func forcedDeveloperRunsRepeatWithoutChangingRealHistory() {
        let real = MemorySplashStore(); real.value.installCompleted = true; real.value.completedUpdateIDs = ["retained"]
        let developer = MemorySplashStore()
        let original = real.value
        let c = SplashCoordinator(store: real, install: .placeholder(.install), update: .placeholder(.update),
                                 developerSelection: { .update }, developerStore: developer)
        c.foreground()
        #expect(c.isDeveloperTesting && c.active?.kind == .update)
        finish(c)
        #expect(!c.isBlocking && real.value == original && real.saves == 0)
        c.foreground()
        #expect(c.isDeveloperTesting && c.index == 0)
        let writes = developer.saves; c.foreground()
        #expect(developer.saves == writes)
    }
    @Test func forcedInterruptedRunResumesAndSwitchingKindRestarts() {
        let real = MemorySplashStore(); real.value.installCompleted = true
        let developer = MemorySplashStore()
        var choice: SplashKind? = .install
        func make() -> SplashCoordinator {
            SplashCoordinator(store: real, install: .placeholder(.install), update: .placeholder(.update),
                              developerSelection: { choice }, developerStore: developer)
        }
        let c = make(); c.foreground(); c.next()
        let resumed = make(); resumed.foreground(); #expect(resumed.index == 1 && resumed.isDeveloperTesting)
        choice = .update
        let changed = make(); changed.foreground(); #expect(changed.index == 0 && changed.active?.kind == .update)
        choice = nil
        let off = make(); off.foreground(); #expect(!off.isBlocking && real.value.installCompleted)
    }
    @Test func realInstallStillPrecedesForcedDeveloperUpdate() {
        let real = MemorySplashStore(); let developer = MemorySplashStore()
        let c = SplashCoordinator(store: real, install: .placeholder(.install), update: .placeholder(.update),
                                 developerSelection: { .update }, developerStore: developer)
        c.foreground(); #expect(c.active?.kind == .install && !c.isDeveloperTesting)
        finish(c); #expect(c.active?.kind == .update && c.isDeveloperTesting && real.value.installCompleted)
        finish(c); #expect(!c.isBlocking && real.value.completedUpdateIDs.isEmpty)
    }
    @Test func developerWriteFailuresBlockWithoutChangingRealCompletion() {
        let real = MemorySplashStore(); real.value.installCompleted = true
        let developer = MemorySplashStore()
        let c = SplashCoordinator(store: real, install: .placeholder(.install), update: .placeholder(.update),
                                 developerSelection: { .update }, developerStore: developer)
        c.foreground(); c.next(); developer.failWrite = true; c.complete()
        #expect(c.isBlocking && c.isDeveloperTesting && c.errorMessage != nil)
        #expect(real.value.installCompleted && real.value.completedUpdateIDs.isEmpty && real.saves == 0)
        developer.failWrite = false; c.retry(); #expect(!c.isBlocking)
    }
    @Test func builtBundleContainsBothValidatedResources() throws {
        for kind in SplashKind.allCases {
            #expect(SplashBundleLoader.url(for: kind) != nil)
            let c = try SplashBundleLoader.load(kind)
            #expect(c.kind == kind && c.slides.count == (kind == .install ? 3 : 2))
            #expect(c.enabled == (kind == .install))
        }
    }
    @Test func originalExportsRemainCompatibleWithOptionalDesignExtensions() throws {
        let old = try SplashBundleLoader.load(.install)
        #expect(old.slides.allSatisfy { $0.design == nil && $0.features == nil && $0.demonstration == nil })
        let decoded = try SplashContent.decode(old.encoded())
        #expect(decoded == old)
        #expect(!decoded.slides[0].resolvedDesign.freeform)
        var compact = old.slides[0]; compact.typography = .compact
        #expect(compact.resolvedDesign.title.size == 22)
    }
    @Test func designedSlidesAndInteractiveStepsRoundTripWithEmbeddedArtwork() throws {
        var content = SplashStudioTestingFixtures.content
        var design = SplashSlideDesign(); design.title.size = 48; design.title.family = .serif
        design.body.size = 16; design.body.family = .monospaced; design.verticalAlignment = .center
        design.freeform = true; design.imageCornerRadius = 24; design.imageWidth = 0.65
        design.titlePlacement = SplashPlacement(x: 0.7, y: 0.4, width: 0.4)
        content.slides[0].design = design
        content.slides[0].features?[0].imageData = SplashStudioTestingFixtures.image
        content.slides[0].features?[0].initialTab = .library
        content.slides[0].features?[0].initialText = "Search placeholder"
        let decoded = try SplashContent.decode(content.encoded())
        #expect(decoded == content)
        #expect(decoded.slides[0].demonstration?.steps.count == 2)
        #expect(decoded.slides[0].features?[0].imageData == SplashStudioTestingFixtures.image)
    }
    @Test func canvasEditsPersistWithoutChangingInstallationHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SplashStateStore(directory: directory)
        var state = SplashState(); state.installCompleted = true; state.completedUpdateIDs = ["previous-announcement"]
        try store.save(state)
        let drafts = directory.appendingPathComponent("Drafts")
        let studio = SplashStudioModel(directory: drafts); studio.draft = SplashStudioTestingFixtures.content
        var placement = SplashPlacement(x: 0.4, y: 0.3, width: 0.5)
        placement.move(dx: 0.15, dy: 0.2)
        studio.draft.slides[0].setPlacement(placement, for: .title)
        studio.draft.slides[0].design?.freeform = true
        #expect(studio.saveDraft())
        let reopened = SplashStudioModel(directory: drafts)
        #expect(reopened.draft == studio.draft)
        #expect(reopened.draft.slides[0].placement(for: .title).y == 0.5)
        #expect(try store.read() == state)
        placement.move(dx: 100, dy: -100)
        #expect(placement.x == 0.95 && placement.y == 0.05)
    }
    @Test func designChangesInvalidateUnfinishedProgressButNeverCompletedInstall() {
        let store = MemorySplashStore(); let first = coordinator(store); first.foreground(); first.next()
        var edited = SplashContent.placeholder(.install)
        var design = SplashSlideDesign(); design.body.family = .serif; edited.slides[0].design = design
        let resumed = coordinator(store, install: edited); resumed.foreground()
        #expect(resumed.index == 0)
        finish(resumed)
        edited.slides[0].features = [SplashDemoFeature(kind: .search)]
        let completed = coordinator(store, install: edited); completed.foreground()
        #expect(!completed.isBlocking)
    }
    @Test func invalidDesignAndDemoDefinitionsCannotBeExported() throws {
        var content = SplashStudioTestingFixtures.content
        content.slides[0].design?.title.size = 100
        #expect(throws: SplashError.self) { try content.encoded() }
        content = SplashStudioTestingFixtures.content; content.slides[0].design?.imageCornerRadius = -1
        #expect(throws: SplashError.self) { try content.encoded() }
        content = SplashStudioTestingFixtures.content; content.slides[0].design?.bodyPlacement.y = .nan
        #expect(throws: SplashError.self) { try content.encoded() }
        content = SplashStudioTestingFixtures.content; content.slides[0].demonstration?.steps = []
        #expect(throws: SplashError.self) { try content.encoded() }
        content = SplashStudioTestingFixtures.content
        content.slides[0].features = Array(repeating: SplashDemoFeature(kind: .favorite), count: 13)
        #expect(throws: SplashError.self) { try content.encoded() }
        let bytes = try SplashStudioTestingFixtures.content.encoded()
        let unsupported = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "miniPlayer", with: "remoteScript")
        #expect(throws: SplashError.self) { try SplashContent.decode(Data(unsupported.utf8)) }
    }
    @Test func importedImagesAreDownsampledAndInvalidSourcesAreRejected() throws {
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200)).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        }
        let resized = try SplashImageCompressor.compress(bytes, dimension: 256, quality: 0.8)
        let image = try #require(UIImage(data: resized))
        #expect(image.size == CGSize(width: 256, height: 192))
        #expect(resized.count <= SplashContent.maxImageBytes)
        try SplashContent.validateImage(resized, description: "Image placeholder", prefix: "")
        #expect(throws: SplashError.self) { try SplashImageCompressor.compress(Data("invalid".utf8), dimension: 256, quality: 0.8) }
        #expect(throws: SplashError.self) { try SplashImageCompressor.compress(bytes, dimension: 128, quality: 0.8) }
        #expect(throws: SplashError.self) { try SplashImageCompressor.compress(bytes, dimension: 256, quality: .nan) }
    }
    @Test func canvasGridAndBoxResizingRemainBounded() throws {
        var placement = SplashPlacement(x: 0.531, y: 0.487, width: 0.83, height: 0.312)
        placement.snapToGrid()
        #expect(abs(placement.x - 0.55) < 0.0001 && placement.y == 0.5)
        #expect(abs(placement.width - 0.85) < 0.0001 && abs(placement.height! - 0.3) < 0.0001)
        placement.scale(by: 100, measuredHeight: 0.3)
        #expect(placement.width == 1 && placement.height == 1.5)
        placement.scale(by: 0.0001, measuredHeight: 0.3)
        #expect(placement.width == 0.2 && placement.height == 0.05)
        let bounded = placement
        placement.scale(by: .nan, measuredHeight: 0.3)
        #expect(placement == bounded)
        placement.move(dx: 100, dy: 100); placement.snapToGrid()
        try placement.validate(prefix: "")
        placement.height = .infinity
        #expect(throws: SplashError.self) { try placement.validate(prefix: "") }
    }
    @Test func backgroundImageRoundTripAndValidation() throws {
        var content = SplashContent.placeholder(.install)
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { context in
            UIColor.purple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        content.slides[0].backgroundImageData = bytes
        content.slides[0].backgroundImageDescription = "Purple background"
        content.slides[0].backgroundImageFit = .fit
        content.slides[0].backgroundImageDim = 0.6
        content.slides[0].design = SplashSlideDesign()
        content.slides[0].design?.gridSnapping = true
        content.slides[0].design?.titlePlacement.height = 0.3
        let decoded = try SplashContent.decode(content.encoded())
        #expect(decoded == content && decoded.fingerprint == content.fingerprint)
        content.slides[0].backgroundImageDim = 1
        #expect(throws: SplashError.self) { try content.encoded() }
        content.slides[0].backgroundImageDim = 0.3
        content.slides[0].backgroundImageDescription = nil
        #expect(throws: SplashError.self) { try content.encoded() }
    }
    @Test func bundledBrandingAndProposedInstallAreSelfContained() throws {
        let catalog = try SplashBundledAssets.catalog()
        #expect(Set(catalog.map(\.id)) == ["twins", "wide-banner", "icon-background"])
        for asset in catalog { _ = try SplashBundledAssets.data(asset) }
        let proposal = try SplashBundledAssets.proposedInstall()
        #expect(proposal.kind == .install && proposal.slides.count == 8)
        #expect(try SplashContent.decode(proposal.encoded()) == proposal)
        let credits = proposal.slides.compactMap(\.body).joined(separator: "\n")
        for name in ["Soul", "XiaoYuan151", "MagicBytes", "SillyProotSoda", "NELC-Official", "cosmii02", "MagnetTileMan"] {
            #expect(credits.contains(name))
        }
        #expect(credits.contains("watchOS") && credits.contains("development"))
        let live = try SplashBundleLoader.load(.install)
        #expect(live.slides.count == 3 && live.id == "install-placeholder")
        #expect(live.slides.allSatisfy { $0.backgroundImageData == nil && $0.design?.gridSnapping == nil })
    }

    @Test func developerResetsOnlyChosenHistoryAndPreservesOtherData() throws {
        let store = MemorySplashStore()
        store.value.installCompleted = true
        store.value.completedUpdateIDs = ["release-two", "older-announcement"]
        let c = coordinator(store, update: announcement()); c.foreground()
        #expect(!c.isBlocking)
        try c.resetHistory(.install)
        #expect(!store.value.installCompleted && store.value.completedUpdateIDs == ["release-two", "older-announcement"])
        try c.resetHistory(.update)
        #expect(!store.value.installCompleted && store.value.completedUpdateIDs == ["older-announcement"])
        let restarted = coordinator(store, update: announcement()); restarted.foreground()
        #expect(restarted.active?.kind == .install && restarted.index == 0)
        finish(restarted)
        #expect(restarted.active?.kind == .update && restarted.index == 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("other-app-data")
        let bytes = Data("login-and-data-marker".utf8); try bytes.write(to: marker)
        let disk = SplashStateStore(directory: directory)
        try disk.save(SplashState(installCompleted: true))
        let diskCoordinator = SplashCoordinator(store: disk, install: .placeholder(.install), update: nil)
        diskCoordinator.foreground(); try diskCoordinator.resetHistory(.install)
        #expect(try Data(contentsOf: marker) == bytes)
    }
    @Test func developerResetDoesNotCloseOrEraseHistoryOnStoreFailures() throws {
        let store = MemorySplashStore(); store.value.installCompleted = true
        store.value.completedUpdateIDs = ["release-two"]
        let c = coordinator(store, update: announcement()); c.foreground()
        let original = store.value
        store.failWrite = true
        #expect(throws: SplashError.self) { try c.resetHistory(.install) }
        #expect(store.value == original && !c.isBlocking)
        store.failRead = true
        #expect(throws: SplashError.self) { try c.resetHistory(.update) }
        #expect(store.value == original)
        var disabled = announcement(); disabled.enabled = false
        let other = MemorySplashStore(); other.value = original
        let disabledCoordinator = coordinator(other, update: disabled); disabledCoordinator.foreground()
        try disabledCoordinator.resetHistory(.update)
        let reopened = coordinator(other, update: disabled); reopened.foreground()
        #expect(!reopened.isBlocking)
    }

}
