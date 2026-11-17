import Foundation

nonisolated struct SplashReleaseNotes: Codable, Equatable {
    var watchVersion = ""
    var watchOS: [Entry] = []
    var iOS: [Entry] = []
    var general: [Entry] = []

    nonisolated struct Entry: Codable, Equatable, Identifiable {
        var id = UUID().uuidString
        var headline = ""
        var details = ""

        var detailLines: [String] {
            details.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    var hasEntries: Bool { !watchOS.isEmpty || !iOS.isEmpty || !general.isEmpty }

    func validate() throws {
        for entries in [watchOS, iOS, general] {
            guard entries.count <= 30, Set(entries.map(\.id)).count == entries.count,
                  entries.allSatisfy({ SplashContent.validID($0.id) && $0.headline.count <= 300 && $0.details.count <= 12000 })
            else { throw SplashError(message: String(localized: "Invalid release notes. Each section can have up to 30 entries.")) }
        }
        if !watchVersion.isEmpty, !SplashContent.validVersion(watchVersion) {
            throw SplashError(message: String(localized: "Enter a valid watchOS version for the release notes."))
        }
    }

    var isReady: Bool {
        hasEntries && (watchOS.isEmpty || SplashContent.validVersion(watchVersion)) &&
            (watchOS + iOS + general).allSatisfy { !$0.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
