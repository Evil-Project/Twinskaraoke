import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

@MainActor
@Suite("Watch search lifecycle")
struct WatchSearchLifecycleTests {
    @Test("Editing the query immediately clears an obsolete error and spinner")
    func editInvalidatesState() {
        let model = SearchViewModel()
        model.loadError = "Old error"
        model.isLoading = true
        model.searchText = "new"
        #expect(model.loadError == nil)
        #expect(!model.isLoading)
        model.searchText = ""
    }

    @Test("Clearing a pending query prevents it from starting")
    func clearPendingQuery() async throws {
        let model = SearchViewModel()
        model.searchText = "pending"
        model.searchText = ""
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.results.isEmpty)
        #expect(!model.isLoading)
        #expect(model.loadError == nil)
    }
}
