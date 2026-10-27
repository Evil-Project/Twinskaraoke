import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

@Suite("Website themes", .serialized)
struct AppThemePaletteTests {
    @Test("The website themes are dark-only and always listed in the picker")
    func websiteThemesAreDarkAndListed() {
        for mode in [AppearanceMode.neuro, .smocus, .evil] {
            #expect(mode.colorScheme == .dark)
            #expect(mode.palette != nil)
            #expect(!mode.isExperimental)
            #expect(!mode.usesAuroraBackground)
        }
    }

    @Test("The themes that existed before keep their look")
    func existingThemesHaveNoPalette() {
        for mode in [AppearanceMode.system, .light, .dark, .nwero] {
            #expect(mode.palette == nil)
        }
    }

    // The values from twinskaraoke.com's css/neuro-theme.css. A typo here
    // would ship a theme that is almost, but not quite, the site's.
    @Test("Palettes match the website's CSS", arguments: [
        (AppearanceMode.neuro, [0x00D9FF, 0xFF6B9D, 0x0A0E1A, 0x141B2D, 0x1E2A42]),
        (AppearanceMode.smocus, [0x9D5CFF, 0xFF6B9D, 0x0A0814, 0x150F23, 0x221A35]),
        (AppearanceMode.evil, [0xFF0066, 0x9D00FF, 0x0D0208, 0x1A0B14, 0x2A1220]),
    ])
    func palettesMatchWebsite(mode: AppearanceMode, expected: [Int]) throws {
        let palette = try #require(mode.palette)
        let actual = [
            palette.primary, palette.accent, palette.background,
            palette.secondaryBackground, palette.elevatedBackground,
        ].map(rgb)
        #expect(actual == expected)
    }

    @Test("Colour tokens follow the applied theme")
    func tokensFollowStore() {
        let store = AppThemeStore.shared
        let original = store.definition
        let selection = UserDefaults.standard.string(forKey: AppearanceMode.storageKey)
        defer {
            store.apply(original)
            UserDefaults.standard.set(selection, forKey: AppearanceMode.storageKey)
        }

        store.apply(.evil)
        #expect(rgb(.appAccent) == 0xFF0066)
        #expect(rgb(.appBackground) == 0x0D0208)
        #expect(rgb(.appDestructive) == rgb(.appDefaultAccent))

        store.apply(.dark)
        #expect(store.palette == nil)
        #expect(rgb(.appAccent) == rgb(.appDefaultAccent))
    }

    private func rgb(_ color: Color) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
