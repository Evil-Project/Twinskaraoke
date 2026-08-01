import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Download destination ownership")
struct DownloadTaskRegistryTests {
    @Test("A completed replacement remains the destination owner")
    func completedReplacementProtectsDestination() {
        let registry = DownloadTaskRegistry()
        let songID = "same-song"
        let original = UUID()
        let replacement = UUID()

        registry.register(songID: songID, token: original)
        #expect(registry.performIfCurrent(songID: songID, token: original) { true } == true)

        registry.register(songID: songID, token: replacement)
        #expect(registry.performIfCurrent(songID: songID, token: replacement) { true } == true)

        let replacementResolution = registry.resolveCompletion(
            songID: songID,
            token: replacement,
            moved: true
        )
        let staleResolution = registry.resolveCompletion(
            songID: songID,
            token: original,
            moved: true
        )

        #expect(replacementResolution.isCurrent)
        #expect(!replacementResolution.shouldRemoveDestination)
        #expect(!staleResolution.isCurrent)
        #expect(staleResolution.hasReplacementOwner)
        #expect(!staleResolution.shouldRemoveDestination)
    }

    @Test("A failed replacement does not protect an older destination")
    func failedReplacementDoesNotProtectOlderDestination() {
        let registry = DownloadTaskRegistry()
        let songID = "failed-replacement"
        let original = UUID()
        let replacement = UUID()

        registry.register(songID: songID, token: original)
        registry.register(songID: songID, token: replacement)
        let replacementResolution = registry.resolveCompletion(
            songID: songID,
            token: replacement,
            moved: false
        )
        let staleResolution = registry.resolveCompletion(
            songID: songID,
            token: original,
            moved: true
        )

        #expect(replacementResolution.isCurrent)
        #expect(!replacementResolution.shouldRemoveDestination)
        #expect(!staleResolution.isCurrent)
        #expect(!staleResolution.hasReplacementOwner)
        #expect(staleResolution.shouldRemoveDestination)
    }

    @Test("Explicit cancellation removes replacement protection")
    func cancellationRemovesReplacementProtection() {
        let registry = DownloadTaskRegistry()
        let songID = "canceled-song"
        let token = UUID()

        registry.register(songID: songID, token: token)
        registry.invalidate(songID: songID)
        let resolution = registry.resolveCompletion(
            songID: songID,
            token: token,
            moved: true
        )

        #expect(!resolution.isCurrent)
        #expect(!resolution.hasReplacementOwner)
        #expect(resolution.shouldRemoveDestination)
    }

    @Test("Clear preserves unresolved callbacks so a replacement stays protected")
    func clearPreservesPendingOwnershipUntilCallbacksResolve() {
        let registry = DownloadTaskRegistry()
        let songID = "remove-all-replacement"
        let original = UUID()
        let replacement = UUID()

        registry.register(songID: songID, token: original)
        registry.invalidateAllAfterDestinationCleanup()
        registry.register(songID: songID, token: replacement)

        let replacementResolution = registry.resolveCompletion(
            songID: songID,
            token: replacement,
            moved: true
        )
        let staleResolution = registry.resolveCompletion(
            songID: songID,
            token: original,
            moved: true
        )

        #expect(replacementResolution.isCurrent)
        #expect(!replacementResolution.shouldRemoveDestination)
        #expect(!staleResolution.isCurrent)
        #expect(staleResolution.hasReplacementOwner)
        #expect(!staleResolution.shouldRemoveDestination)
    }

    @Test("Clear without a replacement allows stale destination cleanup")
    func clearWithoutReplacementReleasesDestination() {
        let registry = DownloadTaskRegistry()
        let songID = "remove-all-only"
        let original = UUID()

        registry.register(songID: songID, token: original)
        registry.invalidateAllAfterDestinationCleanup()
        let staleResolution = registry.resolveCompletion(
            songID: songID,
            token: original,
            moved: true
        )

        #expect(!staleResolution.isCurrent)
        #expect(!staleResolution.hasReplacementOwner)
        #expect(staleResolution.shouldRemoveDestination)
    }

    @Test("A failed replacement performs cleanup deferred by an older completion")
    func failedReplacementConsumesDeferredCleanup() {
        let registry = DownloadTaskRegistry()
        let songID = "deferred-stale-move"
        let original = UUID()
        let replacement = UUID()

        registry.register(songID: songID, token: original)
        registry.register(songID: songID, token: replacement)

        let staleResolution = registry.resolveCompletion(
            songID: songID,
            token: original,
            moved: true
        )
        let replacementResolution = registry.resolveCompletion(
            songID: songID,
            token: replacement,
            moved: false
        )

        #expect(!staleResolution.isCurrent)
        #expect(staleResolution.hasReplacementOwner)
        #expect(!staleResolution.shouldRemoveDestination)
        #expect(replacementResolution.isCurrent)
        #expect(replacementResolution.shouldRemoveDestination)
    }

    @Test("Canceling a replacement consumes cleanup deferred by an older completion")
    func canceledReplacementConsumesDeferredCleanup() {
        let registry = DownloadTaskRegistry()
        let songID = "canceled-deferred-stale-move"
        let original = UUID()
        let replacement = UUID()

        registry.register(songID: songID, token: original)
        registry.register(songID: songID, token: replacement)
        _ = registry.resolveCompletion(songID: songID, token: original, moved: true)

        #expect(registry.invalidate(songID: songID))
    }

    @Test("A successful replacement consumes deferred cleanup without deleting its destination")
    func successfulReplacementConsumesDeferredCleanup() {
        let registry = DownloadTaskRegistry()
        let songID = "successful-deferred-stale-move"
        let original = UUID()
        let replacement = UUID()

        registry.register(songID: songID, token: original)
        registry.register(songID: songID, token: replacement)

        let staleResolution = registry.resolveCompletion(
            songID: songID,
            token: original,
            moved: true
        )
        let replacementResolution = registry.resolveCompletion(
            songID: songID,
            token: replacement,
            moved: true
        )

        #expect(!staleResolution.isCurrent)
        #expect(staleResolution.hasReplacementOwner)
        #expect(!staleResolution.shouldRemoveDestination)
        #expect(replacementResolution.isCurrent)
        #expect(!replacementResolution.shouldRemoveDestination)
    }
}
