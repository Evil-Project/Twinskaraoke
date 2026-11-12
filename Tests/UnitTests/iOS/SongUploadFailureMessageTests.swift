import Foundation
import Testing
@testable import Twinskaraoke

/// The text a failed upload shows on its row and in the sheet.
@MainActor
@Suite("Upload failure messages")
struct SongUploadFailureMessageTests {
    private let english = UploadLocalization(language: .english)
    private let german = UploadLocalization(language: .german)

    private func message(_ fieldErrors: [String: [String]], general: String? = nil) -> String {
        let problem = UploadServerProblem(message: general, fieldErrors: fieldErrors)
        return SongUploadFailure.server(status: 400, problem: problem).userMessage(in: english)
    }

    @Test("A server failure with only field errors shows the first field's message")
    func fieldErrorsWithoutMessageShowTheFirstField() {
        #expect(message(["Genre": ["Pick a genre."], "artist": ["Too long."], "Title": ["Taken."]]) == "Taken.")
        #expect(message(["Zeta": ["Z."], "Genre": ["G."], "artist": ["Too long."]]) == "Too long.")
        #expect(message(["Zeta": ["Z."], "Genre": ["One.", "Two."]]) == "One. Two.")
    }

    @Test("The server's general message still wins over its field errors")
    func generalMessageWins() {
        #expect(message(["Title": ["Taken."]], general: "Could not save.") == "Could not save.")
        let generic = SongUploadFailure.server(status: 400, problem: nil).userMessage(in: english)
        #expect(generic == "The server couldn't add the song (error 400). Try again later.")
    }

    @Test("Messages follow the language chosen in the app")
    func messagesFollowTheAppLanguage() throws {
        #expect(SongUploadFailure.offline.userMessage(in: german)
            == "Du bist offline. Verbinde dich mit dem Internet und versuche es erneut.")
        #expect(SongUploadFailure.server(status: 503, problem: nil).userMessage(in: german)
            == "Der Server konnte den Song nicht hinzufügen (Fehler 503). Versuche es später erneut.")
        #expect(SongUploadFailure.offline.userMessage(in: english)
            == "You're offline. Connect to the internet and try again.")

        // The setting is read from the defaults the app stores it in.
        let suite = "SongUploadFailureMessageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppLanguage.german.rawValue, forKey: AppLanguage.storageKey)
        #expect(SongUploadFailure.offline.userMessage(in: .current(defaults))
            == SongUploadFailure.offline.userMessage(in: german))
    }
}
