import Observation
import SwiftUI

/// The three themes from the twinskaraoke.com theme switcher, copied value for
/// value from the site's `css/neuro-theme.css` (`--neuro-*`, `--twins-*` and
/// `--evil-*`). The site's switcher labels the twins theme "SMOCUS".
///
/// The site only has dark variants, so every one of these forces the dark
/// color scheme, and anything a palette does not cover keeps Dark's look.
struct AppThemePalette: Equatable {
    /// `--*-primary`. Replaces `Color.appAccent`, so it tints every control,
    /// and lights the current lyric and the playback progress.
    let primary: Color
    /// `--*-accent`, the far end of the site's gradients.
    let accent: Color
    /// `--*-bg-primary`, the page behind everything.
    let background: Color
    /// `--*-bg-secondary`, one surface up: sheets and grouped list rows.
    let secondaryBackground: Color
    /// `--*-bg-elevated`, which the site's player buttons sit on.
    let elevatedBackground: Color

    /// The site's play button: primary into accent at 135°.
    ///
    /// Interpolated in the device colour space, as CSS interpolates in sRGB.
    /// SwiftUI's default is perceptual, which runs the middle of cyan-to-pink
    /// through a washed-out lavender grey the site never shows.
    var gradient: some ShapeStyle {
        .linearGradient(
            Gradient(colors: [primary, accent]).colorSpace(.device),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let neuro = AppThemePalette(
        primary: Color(hex: "00D9FF"),
        accent: Color(hex: "FF6B9D"),
        background: Color(hex: "0A0E1A"),
        secondaryBackground: Color(hex: "141B2D"),
        elevatedBackground: Color(hex: "1E2A42")
    )

    static let smocus = AppThemePalette(
        primary: Color(hex: "9D5CFF"),
        accent: Color(hex: "FF6B9D"),
        background: Color(hex: "0A0814"),
        secondaryBackground: Color(hex: "150F23"),
        elevatedBackground: Color(hex: "221A35")
    )

    static let evil = AppThemePalette(
        primary: Color(hex: "FF0066"),
        accent: Color(hex: "9D00FF"),
        background: Color(hex: "0D0208"),
        secondaryBackground: Color(hex: "1A0B14"),
        elevatedBackground: Color(hex: "2A1220")
    )
}

/// The active website palette, or `nil` on every other theme.
///
/// The colour tokens below read through this, so a view that draws with one of
/// them is redrawn by Observation when the theme changes. They used to be
/// constants, and there was nothing to tell a view that had already drawn
/// with one that it was out of date.
@Observable
final class AppThemeStore {
    static let shared = AppThemeStore()

    private(set) var palette: AppThemePalette?

    private init() {
        let stored = UserDefaults.standard.string(forKey: AppearanceMode.storageKey)
        palette = stored.flatMap(AppearanceMode.init(rawValue:))?.palette
    }

    func apply(_ mode: AppearanceMode) {
        let next = mode.palette
        // Observation notifies on every set, equal or not, and each one would
        // redraw every view that touched a colour token.
        guard next != palette else { return }
        palette = next
    }
}

extension Color {
    /// The app's tint: a website theme's primary, otherwise the red the app
    /// has always used. Watch, TV and Mac keep the constant in
    /// `AppAccent.swift`, as they have no theme picker.
    static var appAccent: Color {
        AppThemeStore.shared.palette?.primary ?? .appDefaultAccent
    }

    /// Destructive actions stay red on every theme. They used to borrow
    /// `appAccent` while that was red too; a website theme turns it cyan or
    /// purple, which reads as an ordinary action.
    static let appDestructive = appDefaultAccent

    static var appBackground: Color {
        AppThemeStore.shared.palette?.background ?? .standardBackground
    }

    static var appGroupedBackground: Color {
        AppThemeStore.shared.palette?.background ?? .standardGroupedBackground
    }

    static var appSecondaryBackground: Color {
        AppThemeStore.shared.palette?.secondaryBackground ?? .standardSecondaryBackground
    }

    static var appSheetGradientTop: Color {
        AppThemeStore.shared.palette?.secondaryBackground ?? .standardSheetGradientTop
    }

    static var appSheetGradientBottom: Color {
        AppThemeStore.shared.palette?.background ?? .standardSheetGradientBottom
    }

    /// The circle under the player's round actions. A website theme uses its
    /// elevated surface at the site's 60% (`.fullscreen-action-btn`).
    static var appPlayerActionFill: Color {
        AppThemeStore.shared.palette.map { $0.elevatedBackground.opacity(0.6) } ?? .standardPlayerActionFill
    }
}
