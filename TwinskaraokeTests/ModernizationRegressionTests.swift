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

    @Test("Search prominence never changes system minimization or installs a pan")
    func prominencePreservesSystemOwnership() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UITabBarController()
        window.rootViewController = controller
        controller.tabBarMinimizeBehavior = .never
        let initialRecognizers = controller.view.gestureRecognizers?.count ?? 0
        let first = TabSearchProminenceCoordinator()
        let second = TabSearchProminenceCoordinator()
        first.attach(to: window)
        second.attach(to: window)
        #expect(first.controller == nil) // No presentation mutation during attachment/layout.
        try await waitUntil { first.controller === controller && second.controller === controller }
        #expect(controller.tabBarMinimizeBehavior == .never)
        #expect((controller.view.gestureRecognizers?.count ?? 0) == initialRecognizers)
        first.detach()
        second.detach()
        #expect(controller.tabBarMinimizeBehavior == .never)
    }

    @Test("Search coordinator follows replacements and cancels stale retries")
    func prominenceAttachmentLifetime() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let first = UITabBarController()
        let replacement = UITabBarController()
        window.rootViewController = first
        let coordinator = TabSearchProminenceCoordinator()
        coordinator.attach(to: window)
        try await waitUntil { coordinator.controller === first }
        window.rootViewController = replacement
        coordinator.attach(to: window)
        try await waitUntil { coordinator.controller === replacement }
        coordinator.detach()
        try await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.controller == nil)
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
