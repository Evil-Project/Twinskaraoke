#if os(iOS)
import Foundation
import SwiftUI
import UIKit

nonisolated enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system, light, dark, neuro, smocus, evil, nwero

    static let storageKey = "nk.appearance"

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .neuro: "Neuro"
        case .smocus: "SMOCUS"
        case .evil: "Evil"
        case .nwero: "Nwero"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        // The website themes only exist in dark.
        case .neuro, .smocus, .evil: .dark
        // Nwero keeps Dark's exact palette; it only swaps opaque screen
        // fills for the animated Aurora backdrop underneath every page.
        case .nwero: .dark
        }
    }

    var usesAuroraBackground: Bool {
        self == .nwero
    }

    /// Experimental themes are hidden from the theme picker unless the
    /// person has turned on Settings > Experiments > Experimental Themes.
    var isExperimental: Bool {
        self == .nwero
    }
}


/// Concrete sRGB values cross the process boundary; SwiftUI Color never does.
nonisolated struct ThemeRGBA: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1
    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }
    init(_ color: UIColor, scheme: UIUserInterfaceStyle) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme)).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }
    var isValid: Bool { [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    func composited(over background: Self) -> Self {
        Self(red * alpha + background.red * (1 - alpha), green * alpha + background.green * (1 - alpha), blue * alpha + background.blue * (1 - alpha))
    }
    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    func contrast(with other: Self) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    func opacity(_ value: Double) -> Self { var copy = self; copy.alpha *= value; return copy }
}

nonisolated enum ThemeToken: String, CaseIterable, Codable, Sendable {
    case standardBackground
    case standardSecondaryBackground
    case standardGroupedBackground
    case standardSheetGradientTop
    case standardSheetGradientBottom
    case appGlassFill
    case appGlassFillStrong
    case appGlassForeground
    case appControlActiveFill
    case appControlActiveForeground
    case appControlInactiveFill
    case standardPlayerActionFill
    case appArtworkOverlay
    case appDivider
    case appShadow
    case appHeroShadowIdle
    case appHeroShadowPlaying
    case appAmbientWash
    case appAmbientVignetteTop
    case appAmbientVignetteMid
    case appAmbientVignetteBottom
    case appAmbientRadial
    case appFavoritesTileBackground
    case appPlaceholderPrimary
    case appPlaceholderSecondary
    case appPlaceholderTertiary
    case appPlaceholderQuaternary
    case appPlaceholderSheen
    case appPlaceholderSheenSoft
    case appToolbarPillBackground
    case appToolbarAvatarBackground
    case primary
    case accent
    case background
    case groupedBackground
    case secondaryBackground
    case elevatedBackground
    case sheetGradientTop
    case sheetGradientBottom
    case playerActionFill
    case text
    case secondaryText
    case surfaceTop
    case surfaceBottom
    case edgeHighlight
    case edgeShade
    case insetHighlight
    case cloudTopLeading
    case cloudTopTrailing
    case cloudBottomLeading
    case cloudBottomTrailing
    case plainBackdrop
    case auroraBase
}

nonisolated struct SharedThemeVariant: Codable, Equatable, Sendable {
    var colors: [String: ThemeRGBA]
    var artworkRadius: Double = 12
    var surfaceInset: Double = 3
    var edgeWidth: Double = 1
    var shadowRadius: Double = 5
    var columnGap: Double = 12
    var fontDesign: Typography = .standard
    nonisolated enum Typography: String, Codable, Sendable { case standard, rounded, serif, monospaced }
    subscript(_ token: ThemeToken) -> ThemeRGBA {
        get { colors[token.rawValue] ?? ThemeRGBA(0, 0, 0) }
        set { colors[token.rawValue] = newValue }
    }
    var isValid: Bool {
        ThemeToken.allCases.allSatisfy { colors[$0.rawValue]?.isValid == true }
        && artworkRadius.isFinite && (0...32).contains(artworkRadius)
        && surfaceInset.isFinite && (0...8).contains(surfaceInset)
        && edgeWidth.isFinite && (0.5...2).contains(edgeWidth)
        && shadowRadius.isFinite && (0...12).contains(shadowRadius)
        && columnGap.isFinite && (4...20).contains(columnGap)
    }
    /// Shared contrast calculation for compact controls, including arbitrary
    /// future definitions whose accent may be close to the surface color.
    func readableAccent(backdrop: SharedThemeDefinition.Backdrop) -> ThemeRGBA {
        let surfaces: [ThemeToken] = backdrop == .aurora ? [.cloudTopLeading, .cloudTopTrailing, .cloudBottomTrailing] : [.surfaceTop, .surfaceBottom]
        let base = self[.background]
        return surfaces.allSatisfy { self[.primary].contrast(with: self[$0].composited(over: base)) >= 3 }
            ? self[.primary] : self[.text]
    }
    var design: Font.Design {
        switch fontDesign { case .standard: .default; case .rounded: .rounded; case .serif: .serif; case .monospaced: .monospaced }
    }
}

/// The only named-theme factory. App and extension consume its values, including
/// the static Aurora treatment; widgets never run the app's continuous animation.
nonisolated struct SharedThemeDefinition: Codable, Equatable, Sendable {
    var id: String
    var appearance: Appearance
    var usesPalette: Bool
    var backdrop: Backdrop = .solid
    var light: SharedThemeVariant
    var dark: SharedThemeVariant
    nonisolated enum Appearance: String, Codable, Sendable { case system, light, dark }
    nonisolated enum Backdrop: String, Codable, Sendable { case solid, aurora }
    var isValid: Bool { !id.isEmpty && id.count <= 128 && light.isValid && dark.isValid }
    func variant(for scheme: ColorScheme) -> SharedThemeVariant {
        switch appearance { case .light: light; case .dark: dark; case .system: scheme == .dark ? dark : light }
    }
    var colorScheme: ColorScheme? {
        switch appearance { case .system: nil; case .light: .light; case .dark: .dark }
    }
    static func builtIn(_ mode: AppearanceMode) -> Self {
        var light = standardLight
        var dark = standardDark
        let palette: [UInt32]?
        switch mode {
        case .neuro: palette = [0x00D9FF, 0xFF6B9D, 0x0A0E1A, 0x141B2D, 0x1E2A42]
        case .smocus: palette = [0x9D5CFF, 0xFF6B9D, 0x0A0814, 0x150F23, 0x221A35]
        case .evil: palette = [0xFF0066, 0x9D00FF, 0x0D0208, 0x1A0B14, 0x2A1220]
        default: palette = nil
        }
        if let palette {
            for (token, value) in zip([ThemeToken.primary, .accent, .background, .secondaryBackground, .elevatedBackground], palette) {
                dark[token] = ThemeRGBA(hex: value)
            }
            dark[.groupedBackground] = dark[.background]
            dark[.sheetGradientTop] = dark[.secondaryBackground]
            dark[.sheetGradientBottom] = dark[.background]
            dark[.playerActionFill] = dark[.elevatedBackground].opacity(0.6)
            dark[.surfaceTop] = dark[.elevatedBackground]
            dark[.surfaceBottom] = dark[.background]
            light = dark
        }
        return Self(id: mode.rawValue, appearance: mode == .system ? .system : mode == .light ? .light : .dark,
                    usesPalette: palette != nil, backdrop: mode.usesAuroraBackground ? .aurora : .solid,
                    light: light, dark: dark)
    }
    private static let standardLight = standardVariant(dark: false)
    private static let standardDark = standardVariant(dark: true)
    private static func standardVariant(dark: Bool) -> SharedThemeVariant {
        let scheme: UIUserInterfaceStyle = dark ? .dark : .light
        var colors: [String: ThemeRGBA] = [:]
        func set(_ token: ThemeToken, _ light: UIColor, _ dark: UIColor) {
            colors[token.rawValue] = ThemeRGBA(scheme == .dark ? dark : light, scheme: scheme)
        }
        set(.standardBackground, UIColor.systemBackground, UIColor.black)
        set(.standardSecondaryBackground, UIColor.secondarySystemBackground, UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
        set(.standardGroupedBackground, UIColor.systemGroupedBackground, UIColor.black)
        set(.standardSheetGradientTop, UIColor.systemBackground, UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
        set(.standardSheetGradientBottom, UIColor.secondarySystemBackground, .black)
        set(.appGlassFill, UIColor.white.withAlphaComponent(0.78), UIColor.white.withAlphaComponent(0.12))
        set(.appGlassFillStrong, UIColor.white.withAlphaComponent(0.95), UIColor.white.withAlphaComponent(0.18))
        set(.appGlassForeground, UIColor.label.withAlphaComponent(0.85), UIColor.white.withAlphaComponent(0.85))
        set(.appControlActiveFill, UIColor.label, .white)
        set(.appControlActiveForeground, .white, .black)
        set(.appControlInactiveFill, UIColor.black.withAlphaComponent(0.08), UIColor.white.withAlphaComponent(0.16))
        set(.standardPlayerActionFill, UIColor.black.withAlphaComponent(0.12), UIColor.white.withAlphaComponent(0.10))
        set(.appArtworkOverlay, UIColor.white.withAlphaComponent(0.45), UIColor.black.withAlphaComponent(0.40))
        set(.appDivider, UIColor.separator.withAlphaComponent(0.42), UIColor.white.withAlphaComponent(0.11))
        set(.appShadow, UIColor.black.withAlphaComponent(0.16), UIColor.black.withAlphaComponent(0.36))
        set(.appHeroShadowIdle, UIColor.black.withAlphaComponent(0.14), UIColor.black.withAlphaComponent(0.22))
        set(.appHeroShadowPlaying, UIColor.black.withAlphaComponent(0.20), UIColor.black.withAlphaComponent(0.45))
        set(.appAmbientWash, UIColor.white.withAlphaComponent(0.24), UIColor.black.withAlphaComponent(0.28))
        set(.appAmbientVignetteTop, UIColor.white.withAlphaComponent(0.34), UIColor.black.withAlphaComponent(0.52))
        set(.appAmbientVignetteMid, UIColor.white.withAlphaComponent(0.10), UIColor.black.withAlphaComponent(0.18))
        set(.appAmbientVignetteBottom, UIColor.white.withAlphaComponent(0.40), UIColor.black.withAlphaComponent(0.58))
        set(.appAmbientRadial, UIColor.white.withAlphaComponent(0.08), UIColor.black.withAlphaComponent(0.14))
        set(.appFavoritesTileBackground, UIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1), UIColor.secondarySystemBackground)
        set(.appPlaceholderPrimary, UIColor(red: 0.86, green: 0.87, blue: 0.90, alpha: 1), UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
        set(.appPlaceholderSecondary, UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1), UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1))
        set(.appPlaceholderTertiary, UIColor(red: 0.78, green: 0.78, blue: 0.82, alpha: 1), UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1))
        set(.appPlaceholderQuaternary, UIColor(red: 0.72, green: 0.72, blue: 0.76, alpha: 1), UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
        set(.appPlaceholderSheen, UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 0.18), UIColor(red: 0.28, green: 0.28, blue: 0.32, alpha: 0.36))
        set(.appPlaceholderSheenSoft, UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 0.10), UIColor(red: 0.24, green: 0.24, blue: 0.28, alpha: 0.22))
        set(.appToolbarPillBackground, UIColor.black.withAlphaComponent(0.82), UIColor.white.withAlphaComponent(0.12))
        set(.appToolbarAvatarBackground, UIColor.black.withAlphaComponent(0.72), UIColor.white.withAlphaComponent(0.12))
        set(.text, .label, .white)
        set(.secondaryText, .secondaryLabel, UIColor.white.withAlphaComponent(0.65))
        set(.edgeHighlight, UIColor.white.withAlphaComponent(0.9), UIColor.white.withAlphaComponent(0.25))
        set(.edgeShade, UIColor.black.withAlphaComponent(0.18), UIColor.black.withAlphaComponent(0.65))
        set(.insetHighlight, UIColor.white.withAlphaComponent(0.55), UIColor.white.withAlphaComponent(0.07))
        set(.cloudTopLeading, UIColor(red: 0.85, green: 0.10, blue: 0.45, alpha: 0.81), UIColor(red: 0.55, green: 0.05, blue: 0.28, alpha: 0.80))
        set(.cloudTopTrailing, UIColor(red: 0.98, green: 0.45, blue: 0.65, alpha: 0.60), UIColor(red: 0.75, green: 0.25, blue: 0.45, alpha: 0.61))
        set(.cloudBottomLeading, UIColor(red: 0.95, green: 0.35, blue: 0.58, alpha: 0.55), UIColor(red: 0.65, green: 0.18, blue: 0.38, alpha: 0.45))
        set(.cloudBottomTrailing, UIColor(red: 0.78, green: 0.12, blue: 0.50, alpha: 0.70), UIColor(red: 0.78, green: 0.12, blue: 0.50, alpha: 0.70))
        set(.plainBackdrop, UIColor(white: 0.95, alpha: 1), UIColor(white: 0.2, alpha: 1))
        set(.auroraBase, UIColor(red: 0.25, green: 0.02, blue: 0.12, alpha: 1), UIColor(red: 0.25, green: 0.02, blue: 0.12, alpha: 1))
        var value = SharedThemeVariant(colors: colors)
        value[.primary] = ThemeRGBA(0.98, 0.12, 0.22)
        value[.accent] = value[.primary]
        for (destination, source) in [(ThemeToken.background, ThemeToken.standardBackground), (.groupedBackground, .standardGroupedBackground), (.secondaryBackground, .standardSecondaryBackground), (.elevatedBackground, .standardSecondaryBackground), (.sheetGradientTop, .standardSheetGradientTop), (.sheetGradientBottom, .standardSheetGradientBottom), (.playerActionFill, .standardPlayerActionFill)] {
            value[destination] = value[source]
        }
        value[.surfaceTop] = value[.secondaryBackground]
        value[.surfaceBottom] = value[.background]
        return value
    }
}

nonisolated struct SharedThemeState: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var schemaVersion = currentVersion
    var definition: SharedThemeDefinition
    static let fallback = Self(definition: .builtIn(.dark))
    var isValid: Bool { schemaVersion == Self.currentVersion && definition.isValid }
}
#endif
