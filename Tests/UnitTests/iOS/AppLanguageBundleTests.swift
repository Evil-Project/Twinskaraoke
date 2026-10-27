import Foundation
import Testing
@testable import Twinskaraoke

/// `String(localized:)` resolves against the device language unless it is
/// handed the selected language's bundle; model values drawn verbatim, such
/// as the Favourite Songs playlist name, have to pass it.
@MainActor
@Suite("App language bundles", .serialized)
struct AppLanguageBundleTests {
    private func withLanguage(_ language: AppLanguage, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppLanguage.storageKey)
        defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppLanguage.storageKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.storageKey)
            }
        }
        body()
    }

    @Test("System uses the main bundle; a chosen language uses its own")
    func bundleSelection() {
        #expect(AppLanguage.system.localizationBundle == .main)
        #expect(AppLanguage.german.localizationBundle.bundlePath.hasSuffix("de.lproj"))
        #expect(AppLanguage.english.localizationBundle.bundlePath.hasSuffix("en.lproj"))
    }

    @Test("Favourite Songs is named in the selected app language")
    func favoritesNameFollowsSelectedLanguage() {
        withLanguage(.german) {
            #expect(PlaylistsViewModel().favoritesPlaylist.name == "Lieblingssongs")
        }
        withLanguage(.english) {
            #expect(PlaylistsViewModel().favoritesPlaylist.name == "Favourite Songs")
        }
    }
}
