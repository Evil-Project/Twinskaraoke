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

    @Test("Tab scroll coordinators attach independently and remove their recognizers")
    func tabCoordinatorLifetime() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let firstWindow = UIWindow(windowScene: scene)
        let secondWindow = UIWindow(windowScene: scene)
        let firstController = UITabBarController()
        let secondController = UITabBarController()
        firstWindow.rootViewController = firstController
        secondWindow.rootViewController = secondController
        var first: TabBarMinimizeCoordinator? = TabBarMinimizeCoordinator()
        let second = TabBarMinimizeCoordinator()
        first?.attach(to: firstWindow)
        second.attach(to: secondWindow)
        #expect(recognizerCount(in: firstController) == expectedRecognizerCount)
        #expect(recognizerCount(in: secondController) == expectedRecognizerCount)
        first = nil
        #expect(recognizerCount(in: firstController) == 0)
        #expect(recognizerCount(in: secondController) == expectedRecognizerCount)
    }

    @Test("Tab coordinator follows window moves and root-controller replacements")
    func tabCoordinatorReattachment() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let firstWindow = UIWindow(windowScene: scene)
        let secondWindow = UIWindow(windowScene: scene)
        let first = UITabBarController()
        let second = UITabBarController()
        let replacement = UITabBarController()
        firstWindow.rootViewController = first
        secondWindow.rootViewController = second
        let coordinator = TabBarMinimizeCoordinator()
        coordinator.attach(to: firstWindow)
        coordinator.attach(to: secondWindow)
        #expect(recognizerCount(in: first) == 0)
        #expect(recognizerCount(in: second) == expectedRecognizerCount)
        secondWindow.rootViewController = replacement
        coordinator.attach(to: secondWindow)
        coordinator.attach(to: secondWindow)
        #expect(recognizerCount(in: second) == 0)
        #expect(recognizerCount(in: replacement) == expectedRecognizerCount)
        coordinator.detach()
        #expect(recognizerCount(in: replacement) == 0)
    }

    @Test("Detached or superseded attachment retries cannot install on an old window")
    func tabCoordinatorCancelledRetry() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldWindow = UIWindow(windowScene: scene)
        let newWindow = UIWindow(windowScene: scene)
        let oldController = UITabBarController()
        let newController = UITabBarController()
        let coordinator = TabBarMinimizeCoordinator()
        coordinator.attach(to: oldWindow)
        coordinator.detach()
        oldWindow.rootViewController = oldController
        try await Task.sleep(for: .milliseconds(30))
        #expect(recognizerCount(in: oldController) == 0)
        oldWindow.rootViewController = nil
        coordinator.attach(to: oldWindow)
        newWindow.rootViewController = newController
        coordinator.attach(to: newWindow)
        oldWindow.rootViewController = oldController
        try await Task.sleep(for: .milliseconds(30))
        #expect(recognizerCount(in: oldController) == 0)
        #expect(recognizerCount(in: newController) == expectedRecognizerCount)
    }

    @Test("An overlapping coordinator leaves the installed recognizer and its reveal alone")
    func tabCoordinatorOverlappingInstallers() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UITabBarController()
        window.rootViewController = controller
        // An iPad resizing between the sidebar and tab shells overlaps two
        // installers on one controller. Only the first gets the recognizer.
        let owner = TabBarMinimizeCoordinator()
        let overlapping = TabBarMinimizeCoordinator()
        owner.attach(to: window)
        overlapping.attach(to: window)
        #expect(recognizerCount(in: controller) == expectedRecognizerCount)

        // Stands in for a reveal the owner is holding. The overlapping
        // coordinator used to fail its fast path on every update, which cleared
        // its state and reassigned the behaviour out from under the owner.
        controller.tabBarMinimizeBehavior = .never
        overlapping.attach(to: window)
        overlapping.attach(to: window)
        #expect(controller.tabBarMinimizeBehavior == .never)
        #expect(recognizerCount(in: controller) == expectedRecognizerCount)

        // Teardown removes only what a coordinator installed itself.
        overlapping.detach()
        #expect(recognizerCount(in: controller) == expectedRecognizerCount)
        owner.detach()
        #expect(recognizerCount(in: controller) == 0)
    }

    @Test("Removing an installer detaches even while the installer remains alive")
    func tabInstallerRemoval() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UITabBarController()
        window.rootViewController = controller
        // A hidden UIWindow does not automatically install its root view.
        window.addSubview(controller.view)
        let installer = InstallerView()
        controller.view.addSubview(installer)
        #expect(installer.window === window)
        #expect(recognizerCount(in: controller) == expectedRecognizerCount)
        installer.removeFromSuperview()
        #expect(recognizerCount(in: controller) == 0)
    }

    // All supported systems retain the short upward-scroll reveal.
    private var expectedRecognizerCount: Int {
        return 1
    }

    private func recognizerCount(in controller: UITabBarController) -> Int {
        controller.view.gestureRecognizers?.filter { $0.name == "Twinskaraoke.TabBarExpandOnScrollUp" }.count ?? 0
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
