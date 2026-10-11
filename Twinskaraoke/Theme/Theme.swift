import SwiftUI

struct Theme {
    private static func color(_ token: ThemeToken, _ scheme: ColorScheme) -> Color {
        AppThemeStore.shared.definition.variant(for: scheme)[token].color
    }
    static var generalBackground: Color { color(.auroraBase, .dark) }
    static func ellipsesTopLeading(forScheme scheme: ColorScheme) -> Color { color(.cloudTopLeading, scheme) }
    static func ellipsesTopTrailing(forScheme scheme: ColorScheme) -> Color { color(.cloudTopTrailing, scheme) }
    static func ellipsesBottomTrailing(forScheme scheme: ColorScheme) -> Color { color(.cloudBottomTrailing, scheme) }
    static func ellipsesBottomLeading(forScheme scheme: ColorScheme) -> Color { color(.cloudBottomLeading, scheme) }
    static func differentiateWithoutColorBackground(forScheme scheme: ColorScheme) -> Color { color(.plainBackdrop, scheme) }
}
