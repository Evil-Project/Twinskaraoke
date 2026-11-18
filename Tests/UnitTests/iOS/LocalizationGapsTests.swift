import Foundation
import Testing

/// The strings the Credits screen, the welcome walkthrough, the New Playlist
/// sheet and the App Icon alert draw must be in the catalog with every
/// language translated. Several of them were drawn through `Text(String)` or
/// built by concatenation, so they never reached the catalog and showed in
/// English in every language.
@Suite("Localization gaps")
struct LocalizationGapsTests {
    nonisolated static let languages = ["de", "fi", "fr", "ja", "uk", "zh-Hans", "zh-Hant"]

    nonisolated static let keys = [
        // Credits: roles and paragraphs. Names and handles stay verbatim.
        "Creator & Developer",
        "Main Developer",
        "Maintainer",
        "Website banner art",
        "Banner editing",
        "Website logo",
        "Neuro Coin, Evil Coin, and Twins Coin artwork",
        "Twitch poll vote retrieval; manages Neuro & Evil Quotes",
        "Video gallery editing and uploads",
        "Soundbite creation and editing",
        "Creator and maintainer of the Karaoke App",
        "Badge art editing",
        "Helped obtain artist permissions from B2",
        "Helped upload a large number of artworks",
        "Big thanks for assisting with internal testing, bug reporting, and maintaining accurate song metadata across the site:",
        "All cover files dated November 26, 2025 and earlier are retrieved from the Unofficial Neuro Karaoke Archive (V3).",
        "Currently managed by: %@",
        "All artwork displayed on this site is used with explicit permission from the respective artists. "
            + "The following artists have granted permission for their artwork to be used on this website:",
        // Welcome walkthrough progress.
        "Welcome · %lld of %lld",
        "Update · %lld of %lld",
        "Welcome, slide %lld of %lld",
        "Update, slide %lld of %lld",
        // New Playlist sheet.
        "New Playlist",
        "New public playlist",
        "New private playlist",
        "%@, public playlist",
        "%@, private playlist",
        "Only you can see this playlist",
        // App Icon alert fallback.
        "Please try again.",
    ]

    /// The source catalog, read from the checkout: the compiled `.strings`
    /// tables don't record a translation's state.
    private nonisolated static let catalog: [String: CatalogEntry] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../Resources/Localization/Apple/Localizable.xcstrings")
            .standardizedFileURL
        guard let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
        else { return [:] }
        return catalog.strings
    }()

    @Test("The catalog can be read")
    func catalogLoads() {
        #expect(!Self.catalog.isEmpty)
    }

    @Test("Every language has a translated value", arguments: LocalizationGapsTests.keys)
    func keyIsTranslated(_ key: String) throws {
        let entry = try #require(Self.catalog[key], "\(key) is missing from the catalog")
        for language in Self.languages {
            let unit = entry.localizations?[language]?.stringUnit
            let value = unit?.value ?? ""
            #expect(unit?.state == "translated", "\(key) is not translated into \(language)")
            #expect(!value.isEmpty && value != key, "\(key) has no \(language) translation of its own")
            #expect(
                Self.placeholders(in: value) == Self.placeholders(in: key),
                "\(key) loses or changes a placeholder in \(language)"
            )
        }
    }

    /// The format specifiers of a string as (argument, type) pairs in
    /// argument order. `%1$lld` names its argument; an unpositioned one takes
    /// the next, as `String(format:)` counts them. Comparing types alone let
    /// a translation that uses `%1$lld` twice pass for `%lld of %lld`.
    nonisolated static func placeholders(in string: String) -> [Placeholder] {
        var nextArgument = 0
        return string.matches(of: /%(?:(\d+)\$)?(@|lld)/).map { match in
            let argument: Int
            if let position = match.output.1.flatMap({ Int($0) }) {
                argument = position
            } else {
                nextArgument += 1
                argument = nextArgument
            }
            return Placeholder(argument: argument, type: String(match.output.2))
        }
        .sorted { ($0.argument, $0.type) < ($1.argument, $1.type) }
    }

    nonisolated struct Placeholder: Equatable, CustomStringConvertible {
        let argument: Int
        let type: String

        var description: String { "%\(argument)$\(type)" }
    }

    @Test("Placeholders keep their argument, not just their type")
    func placeholdersKeepTheirArgument() {
        let key = "Welcome · %lld of %lld"
        #expect(Self.placeholders(in: "Willkommen · %1$lld von %2$lld") == Self.placeholders(in: key))
        #expect(Self.placeholders(in: "%2$lld / %1$lld") == Self.placeholders(in: key))
        #expect(Self.placeholders(in: "Willkommen · %1$lld von %1$lld") != Self.placeholders(in: key))
        #expect(Self.placeholders(in: "%@ · %lld") != Self.placeholders(in: key))
    }
}

private nonisolated struct Catalog: Decodable {
    let strings: [String: CatalogEntry]
}

private nonisolated struct CatalogEntry: Decodable {
    struct Localization: Decodable {
        struct StringUnit: Decodable {
            let state: String
            let value: String
        }

        let stringUnit: StringUnit?
    }

    let localizations: [String: Localization]?
}
