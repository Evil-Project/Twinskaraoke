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

        static let maximumDetailLines = 30

        /// Bounds even unvalidated/legacy content before the view creates any detail rows.
        var detailLines: [String] { detailLines(upTo: Self.maximumDetailLines) }
        var hasTooManyDetailLines: Bool { detailLines(upTo: Self.maximumDetailLines + 1).count > Self.maximumDetailLines }

        private func detailLines(upTo limit: Int) -> [String] {
            var lines: [String] = []
            details.enumerateLines { line, stop in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { lines.append(trimmed) }
                stop = lines.count >= limit
            }
            return lines
        }
    }

    var hasEntries: Bool { !watchOS.isEmpty || !iOS.isEmpty || !general.isEmpty }

    func validate() throws {
        for entries in [watchOS, iOS, general] {
            guard entries.count <= 30, Set(entries.map(\.id)).count == entries.count,
                  entries.allSatisfy({ SplashContent.validID($0.id) && $0.headline.count <= 300 && $0.details.count <= 12000 })
            else { throw SplashError(message: String(localized: "Invalid release notes. Each section can have up to 30 entries.")) }
            guard entries.allSatisfy({ !$0.hasTooManyDetailLines }) else {
                throw SplashError(message: String(localized: "Each release-note entry can have up to \(Entry.maximumDetailLines) detail lines."))
            }
        }
        if !watchVersion.isEmpty, !SplashContent.validVersion(watchVersion) {
            throw SplashError(message: String(localized: "Enter a valid watchOS version for the release notes."))
        }
    }

    var isReady: Bool {
        hasEntries && (watchOS.isEmpty || SplashContent.validVersion(watchVersion)) &&
            (watchOS + iOS + general).allSatisfy {
                !$0.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasTooManyDetailLines
            }
    }
}
