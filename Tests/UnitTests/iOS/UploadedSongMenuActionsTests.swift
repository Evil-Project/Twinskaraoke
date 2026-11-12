import Testing
@testable import Twinskaraoke

/// The song menu offers Edit and Delete only where a screen supplies them.
@MainActor
@Suite("Uploaded song menu actions")
struct UploadedSongMenuActionsTests {
    @Test("Without actions from the screen, the menu adds nothing")
    func noItemsWithoutActions() {
        #expect(UploadedSongMenuActions.items(offeredBy: nil).isEmpty)
    }

    @Test("With actions from the screen, Edit then Delete")
    func editAndDeleteWithActions() {
        let actions = UploadedSongMenuActions(edit: { _ in }, delete: { _ in })
        #expect(UploadedSongMenuActions.items(offeredBy: actions) == [.edit, .delete])
    }
}
