import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Playback load failure")
struct PlaybackLoadFailureTests {
    @Test("Connectivity errors read as offline", arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .cannotFindHost,
        .cannotConnectToHost,
        .timedOut,
    ])
    func connectivityIsOffline(code: URLError.Code) {
        #expect(PlaybackLoadFailure(URLError(code)) == .offline)
    }

    @Test("Anything else means the song itself could not be played")
    func otherErrorsAreUnavailable() {
        #expect(PlaybackLoadFailure(URLError(.badServerResponse)) == .unavailable)
        #expect(PlaybackLoadFailure(URLError(.fileDoesNotExist)) == .unavailable)
        #expect(PlaybackLoadFailure(CocoaError(.fileReadCorruptFile)) == .unavailable)
    }

    @Test("Each failure has a message to show")
    func messages() {
        #expect(!PlaybackLoadFailure.offline.message.isEmpty)
        #expect(!PlaybackLoadFailure.unavailable.message.isEmpty)
        #expect(PlaybackLoadFailure.offline.message != PlaybackLoadFailure.unavailable.message)
    }
}
