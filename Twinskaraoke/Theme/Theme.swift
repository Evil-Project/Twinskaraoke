import SwiftUI

struct Theme {
    // Deep dark pink / plum base background
    static var generalBackground: Color {
        Color(red: 0.25, green: 0.02, blue: 0.12)
    }

    // Top Leading Cloud (Deep Hot Pink)
    static func ellipsesTopLeading(forScheme scheme: ColorScheme) -> Color {
        let any = Color(red: 0.85, green: 0.10, blue: 0.45, opacity: 0.81)
        let dark = Color(red: 0.55, green: 0.05, blue: 0.28, opacity: 0.80)
        switch scheme {
        case .light:
            return any
        case .dark:
            return dark
        @unknown default:
            return any
        }
    }

    // Top Trailing Cloud (Soft Bright Pink)
    static func ellipsesTopTrailing(forScheme scheme: ColorScheme) -> Color {
        let any = Color(red: 0.98, green: 0.45, blue: 0.65, opacity: 0.60)
        let dark = Color(red: 0.75, green: 0.25, blue: 0.45, opacity: 0.61)
        switch scheme {
        case .light:
            return any
        case .dark:
            return dark
        @unknown default:
            return any
        }
    }

    // Bottom Trailing Cloud (Vibrant Magenta)
    static func ellipsesBottomTrailing(forScheme scheme: ColorScheme) -> Color {
        Color(red: 0.78, green: 0.12, blue: 0.50, opacity: 0.70)
    }

    // Bottom Leading Cloud (Light Rose Pink)
    static func ellipsesBottomLeading(forScheme scheme: ColorScheme) -> Color {
        let any = Color(red: 0.95, green: 0.35, blue: 0.58, opacity: 0.55)
        let dark = Color(red: 0.65, green: 0.18, blue: 0.38, opacity: 0.45)
        switch scheme {
        case .light:
            return any
        case .dark:
            return dark
        @unknown default:
            return any
        }
    }

    // Accessible plain background without colors
    static func differentiateWithoutColorBackground(forScheme scheme: ColorScheme) -> Color {
        let any = Color(white: 0.95)
        let dark = Color(white: 0.2)
        switch scheme {
        case .light:
            return any
        case .dark:
            return dark
        @unknown default:
            return any
        }
    }
}
