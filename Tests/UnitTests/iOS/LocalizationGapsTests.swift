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
                Self.placeholderTypes(in: value) == Self.placeholderTypes(in: key),
                "\(key) loses or changes a placeholder in \(language)"
            )
        }
    }

    /// The format specifiers of a string by type, ignoring their positions.
    nonisolated static func placeholderTypes(in string: String) -> [String] {
        string.matches(of: /%(?:\d+\$)?(@|lld)/).map { String($0.output.1) }.sorted()
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
