import Foundation
import Observation
import Testing
import UIKit
@testable import Twinskaraoke

@MainActor
@Suite("Modernization regressions")
struct ModernizationRegressionTests {
    @Observable
    final class State {
        var value = 0
    }

    @Test("Observation follows mutations made by its callback")
    func observationReentrancy() async throws {
        let state = State()
        var values: [Int] = []
        let token = observeContinuously({ _ = state.value }, onChange: {
            values.append(state.value)
            if state.value == 1 { state.value = 2 }
        })
        defer { token.cancel() }
        state.value = 1
        try await waitUntil { values.count == 2 }
        #expect(values == [1, 2])
    }

    @Test("Cancelled and released observations suppress queued callbacks")
    func observationCancellation() async throws {
        let state = State()
        var callbacks = 0
        var token: ObservationToken? = observeContinuously({ _ = state.value }, onChange: {
            callbacks += 1
        })
        state.value = 1
        token?.cancel()
        token = nil
        var released: ObservationToken? = observeContinuously({ _ = state.value }, onChange: {
            callbacks += 1
        })
        state.value = 2
        #expect(released != nil)
        released = nil
        try await Task.sleep(for: .milliseconds(30))
        #expect(callbacks == 0)
    }

    @Test("Lossy arrays advance past every malformed JSON shape")
    func lossyArrayProgress() throws {
        let data = Data(#"[null,42,"bad",[],{}, {"id":"a","name":"A"}]"#.utf8)
        let page = try JSONDecoder().decode(LossyArray<PlaylistListItem>.self, from: data)
        #expect(page.sourceCount == 6)
        #expect(page.elements.map(\.id) == ["a"])
    }

    @Test("Playlist pagination advances by raw entries and removes duplicates within a page")
    func playlistOffsets() async throws {
        var offsets: [Int] = []
        var requests = 0
        let loader = PlaylistListLoader(readToken: { nil }) { _ in
            requests += 1
            if requests == 1 {
                let duplicates = Array(repeating: #"{"id":"b","name":"B"}"#, count: 23)
                return Data(("[" + ([#"{"id":"a","name":"A"}"#, "null"] + duplicates).joined(separator: ",") + "]").utf8)
            }
            return Data("[]".utf8)
        }
        let initial = Playlist(id: "a", name: "A", songCount: 0, mosaicMedia: nil, songListDTOs: nil)
        loader.bootstrap(initial: [initial]) { offset, _ in
            offsets.append(offset)
            return "https://example.com/playlists?offset=\(offset)"
        }
        loader.loadMoreIfNeeded(current: initial)
        try await waitUntil { !loader.isLoadingMore }
        #expect(loader.playlists.map(\.id) == ["a", "b"])
        loader.loadMoreIfNeeded(current: try #require(loader.playlists.last))
        try await waitUntil { !loader.isLoadingMore }
        #expect(offsets == [1, 26])
        loader.loadMoreIfNeeded(current: initial)
        #expect(requests == 2)
    }

    @Test("Malformed playlist responses retry the same offset")
    func playlistRetry() async throws {
        var offsets: [Int] = []
        let loader = PlaylistListLoader(readToken: { nil }) { _ in Data("{}".utf8) }
        let initial = Playlist(id: "a", name: "A", songCount: 0, mosaicMedia: nil, songListDTOs: nil)
        loader.bootstrap(initial: [initial]) { offset, _ in
            offsets.append(offset)
            return "https://example.com/playlists"
        }
        for _ in 0..<2 {
            loader.loadMoreIfNeeded(current: initial)
            try await waitUntil { !loader.isLoadingMore }
        }
        #expect(offsets == [1, 1])
    }

    @Test("Cancelled sign-in cannot commit a successful late response")
    func cancelledLogin() async throws {
        var pending: CheckedContinuation<(Data, URLResponse), Error>?
        let auth = AuthManager { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        let task = Task { await auth.login(username: "fixture-user", password: "fixture-password") }
        try await waitUntil { pending != nil }
        task.cancel()
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://example.com/login")!, statusCode: 200,
            httpVersion: nil, headerFields: nil
        ))
        pending?.resume(returning: (Data(#"{"token":"fixture-token"}"#.utf8), response))
        await task.value
        #expect(!auth.isLoading)
        #expect(auth.errorMessage == nil)
        #expect(auth.authToken != "fixture-token")
    }

    @Test("The app keeps Search activation enabled across tab and appearance updates")
    func nativeSearchActivationSurvivesUpdates() async throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        @MainActor func findTabController(in root: UIViewController?) -> UITabBarController? {
            guard let root else { return nil }
            if let tabs = root as? UITabBarController { return tabs }
            for child in root.children {
                if let tabs = findTabController(in: child) { return tabs }
            }
            return nil
        }

        var appWindow: UIWindow?
        var tabController: UITabBarController?
        try await waitUntil {
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                for window in scene.windows {
                    if let tabs = findTabController(in: window.rootViewController),
                       tabs.tabs.count == RootSection.allCases.count {
                        appWindow = window
                        tabController = tabs
                        return true
                    }
                }
            }
            return false
        }
        let window = try #require(appWindow)
        let controller = try #require(tabController)
        let search = try #require(controller.tabs.compactMap { $0 as? UISearchTab }.first)
        #expect(search.automaticallyActivatesSearch)
        let router = AppRouter.shared
        let originalSection = router.section
        let originalPendingRoute = router.hasPendingRoute
        defer {
            router.section = originalSection
            router.hasPendingRoute = originalPendingRoute
            router.requestID = UUID()
        }
        for section in [RootSection.library, .home] {
            router.section = section
            router.requestID = UUID()
            let index = try #require(RootSection.allCases.firstIndex(of: section))
            try await waitUntil { controller.selectedTab === controller.tabs[index] }
            let updatedSearch = try #require(controller.tabs.compactMap { $0 as? UISearchTab }.first)
            #expect(updatedSearch.automaticallyActivatesSearch)
        }
        let originalStyle = window.overrideUserInterfaceStyle
        defer { window.overrideUserInterfaceStyle = originalStyle }
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let updatedSearch = try #require(controller.tabs.compactMap { $0 as? UISearchTab }.first)
            #expect(updatedSearch.automaticallyActivatesSearch)
            #expect(controller.tabBarMinimizeBehavior == .onScrollDown)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        // Stops the test here rather than letting the assertions that follow
        // fail a second time against state that never settled.
        try #require(condition())
    }
}
