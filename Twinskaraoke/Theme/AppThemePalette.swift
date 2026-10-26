import Observation
import SwiftUI
import WidgetKit

/// SwiftUI adapter for the website palette in the shared, serializable theme.
/// Named values and appearance rules live in SharedThemeDefinition.
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

    init(definition: SharedThemeDefinition) {
        let values = definition.variant(for: .dark)
        primary = values[.primary].color
        accent = values[.accent].color
        background = values[.background].color
        secondaryBackground = values[.secondaryBackground].color
        elevatedBackground = values[.elevatedBackground].color
    }
    static let neuro = Self(definition: .builtIn(.neuro))
    static let smocus = Self(definition: .builtIn(.smocus))
    static let evil = Self(definition: .builtIn(.evil))
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

    private(set) var definition: SharedThemeDefinition
    var palette: AppThemePalette? { definition.usesPalette ? AppThemePalette(definition: definition) : nil }

    private init() {
        let stored = UserDefaults.standard.string(forKey: AppearanceMode.storageKey)
        let persisted = WidgetSnapshotStore().readTheme().definition
        if stored == persisted.id {
            definition = persisted
        } else {
            definition = .builtIn(stored.flatMap(AppearanceMode.init(rawValue:)) ?? .dark)
        }
    }

    func apply(_ mode: AppearanceMode) { apply(.builtIn(mode)) }

    func applySelection(_ id: String) {
        if let mode = AppearanceMode(rawValue: id) { apply(mode); return }
        let persisted = WidgetSnapshotStore().readTheme().definition
        apply(persisted.id == id ? persisted : .builtIn(.dark))
    }

    /// A future creator can use the same complete-definition path without
    /// teaching the widgets a new theme name.
    func apply(_ next: SharedThemeDefinition) {
        guard next.isValid else { return }
        if next != definition { definition = next }
        let store = WidgetSnapshotStore()
        let state = SharedThemeState(definition: next)
        let needsWrite = store.readTheme() != state || !store.hasCurrentThemeState
        do {
            if needsWrite { try store.write(state) }
            // Keep custom IDs across relaunches using the same selection key.
            UserDefaults.standard.set(next.id, forKey: AppearanceMode.storageKey)
            if needsWrite {
                for kind in [WidgetKinds.recent, WidgetKinds.nowPlaying, WidgetKinds.radio] {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
            }
        } catch {
            DebugLogger.log("Widget theme unavailable: \(error.localizedDescription)", category: .cache)
        }
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
