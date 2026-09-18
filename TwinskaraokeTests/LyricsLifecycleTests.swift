import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Lyrics lifecycle")
struct LyricsLifecycleTests {
    @Test("Out-of-order lyrics are sorted and nonfinite timestamps are discarded")
    func ordering() async throws {
        let id = UUID().uuidString
        defer { clearCache(id) }
        let model = LyricsViewModel(readToken: { nil }, fetchData: { _ in
            Data(#"[{"time":"20","text":"Second"},{"time":"inf","text":"Invalid"},{"time":"00:05","text":"First"}]"#.utf8)
        })
        model.fetch(songID: id)
        try await waitUntil { !model.isLoading }
        #expect(model.lyrics.map(\.text) == ["First", "Second"])
        #expect(model.lyrics.map(\.time) == [5, 20])
    }

    @Test("An old same-song response cannot finish a replacement request")
    func replacement() async throws {
        var pending: [CheckedContinuation<Data, Error>] = []
        let model = LyricsViewModel(readToken: { nil }, fetchData: { _ in
            try await withCheckedThrowingContinuation { pending.append($0) }
        })
        let id = UUID().uuidString
        defer { clearCache(id) }
        model.fetch(songID: id)
        try await waitUntil { pending.count == 1 }
        model.retry()
        try await waitUntil { pending.count == 2 }
        pending[0].resume(returning: Data(#"[{"time":"1","text":"Old"}]"#.utf8))
        // Drain the old completion while leaving the replacement suspended.
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.isLoading)
        #expect(model.lyrics.isEmpty)
        pending[1].resume(returning: Data(#"[{"time":"2","text":"Current"}]"#.utf8))
        try await waitUntil { !model.isLoading }
        #expect(model.lyrics.map(\.text) == ["Current"])
    }

    @Test("Adopting the same song invalidates an outstanding translation")
    func adoptionDuringTranslation() async throws {
        var pending: CheckedContinuation<[LyricLine], Error>?
        let id = UUID().uuidString
        defer { clearCache(id) }
        let model = LyricsViewModel(translate: { _, _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }, translationConfigured: { true })
        model.adopt(songID: id, lyrics: [LyricLine(time: 1, text: "Old")])
        model.requestTranslation()
        try await waitUntil { pending != nil }
        model.adopt(songID: id, lyrics: [LyricLine(time: 2, text: "Replacement")])
        pending?.resume(returning: [LyricLine(time: 1, text: "Old", translatedText: "Stale translation")])
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.lyrics.map(\.text) == ["Replacement"])
        #expect(model.translationState == .idle)
        #expect(LyricsCacheStore.load(songID: id, variant: .translated) == nil)
    }

    @Test("A cached translation must match source text and timing")
    func staleTranslationCache() async throws {
        let id = UUID().uuidString
        defer { clearCache(id) }
        LyricsCacheStore.save([LyricLine(time: 1, text: "Old", translatedText: "Old translation")], songID: id, variant: .translated)
        var calls = 0
        let model = LyricsViewModel(translate: { _, lyrics in
            calls += 1
            return lyrics.map { $0.withTranslation("Current translation") }
        }, translationConfigured: { true })
        model.adopt(songID: id, lyrics: [LyricLine(time: 1, text: "Current")])
        model.requestTranslation()
        try await waitUntil { model.translationState != .translating }
        #expect(calls == 1)
        #expect(model.lyrics.first?.translatedText == "Current translation")
    }

    @Test("Not-found lyrics are empty, while server failures remain retryable")
    func errors() async throws {
        for status in [404, 500] {
            let model = LyricsViewModel(readToken: { nil }, fetchData: { _ in throw KaraokeAPIClient.APIError.httpStatus(status) })
            model.fetch(songID: UUID().uuidString)
            try await waitUntil { !model.isLoading }
            #expect(model.hasNoLyrics == (status == 404))
            #expect(model.didFail == (status == 500))
        }
    }

    @Test("Timestamp parser rejects nonfinite and negative components", arguments: ["inf", "nan", "1e309", "-1:90", "1:-1", "-1:90:0", "1:inf"])
    func invalidTime(raw: String) {
        #expect(TimeSpanParser.parse(raw) == nil)
    }

    @Test("QR session IDs remain one path component")
    func qrRoute() throws {
        let route = try QRSignIn.Route.status("a/b?c#d% e")
        #expect(route.hasSuffix("/a%2Fb%3Fc%23d%25%20e"))
        for invalid in ["", ".", ".."] {
            #expect(throws: QRSignIn.ServiceError.self) { try QRSignIn.Route.status(invalid) }
        }
    }

    @Test("Cancelled artwork failures cannot invalidate a replacement for the same playlist")
    func artworkReplacement() async throws {
        var pending: [CheckedContinuation<Data, Error>] = []
        let loader = PlaylistCoverLoader { _ in
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
        loader.load(playlistID: "a")
        try await waitUntil { pending.count == 1 }
        loader.load(playlistID: "b")
        try await waitUntil { pending.count == 2 }
        loader.load(playlistID: "a")
        try await waitUntil { pending.count == 3 }
        pending[0].resume(throwing: URLError(.cancelled))
        pending[1].resume(throwing: URLError(.cancelled))
        try await Task.sleep(for: .milliseconds(30))
        loader.load(playlistID: "a")
        try await Task.sleep(for: .milliseconds(30))
        #expect(pending.count == 3)
        for request in pending.dropFirst(2) {
            request.resume(returning: Data(#"{"id":"a","name":"A"}"#.utf8))
        }
    }

    private func clearCache(_ id: String) {
        LyricsCacheStore.save([], songID: id, variant: .original)
        LyricsCacheStore.save([], songID: id, variant: .translated)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(condition())
    }
}
