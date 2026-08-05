import SDWebImageSwiftUI
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

enum AppearanceMode: String, CaseIterable {
    case system, light, dark, nwero
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .nwero: "Nwero"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
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

/// Drop-in replacement for a flat screen background color. On every theme
/// except Nwero it renders the normal opaque background; on Nwero it goes
/// fully clear so the animated Aurora backdrop (mounted once at the app
/// root) shows through on every screen. Because this reads `nk.appearance`
/// via `@AppStorage`, any mounted instance re-renders the moment the theme
/// picker changes, so every tab picks up the new look without a relaunch.
struct ScreenBackgroundFill: View {
    enum Style {
        case standard
        case grouped
    }

    var style: Style = .standard

    @AppStorage("nk.appearance") private var appearanceMode: String = AppearanceMode.dark.rawValue

    private var isNwero: Bool {
        (AppearanceMode(rawValue: appearanceMode) ?? .dark).usesAuroraBackground
    }

    var body: some View {
        Group {
            if isNwero {
                // Each screen gets its own real, opaquely-drawn Aurora
                // backdrop (not a see-through trick) so NavigationStack/
                // TabView can composite transitions normally. See the note
                // on NweroAuroraBackdrop.
                NweroAuroraBackdrop()
            } else if style == .grouped {
                Color.appGroupedBackground
            } else {
                Color.appBackground
            }
        }
        .ignoresSafeArea()
    }
}

nonisolated extension Color {
    #if canImport(UIKit)
        private static func adaptive(light: UIColor, dark: UIColor) -> Color {
            Color(
                uiColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark ? dark : light
                }
            )
        }
    #endif

    #if canImport(UIKit)
        static let appBackground = adaptive(
            light: UIColor.systemBackground,
            dark: UIColor.black
        )
        static let appSecondaryBackground = adaptive(
            light: UIColor.secondarySystemBackground,
            dark: UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        )
        static let appGroupedBackground = adaptive(
            light: UIColor.systemGroupedBackground,
            dark: UIColor.black
        )
        static let appSheetGradientTop = adaptive(
            light: UIColor.systemBackground,
            dark: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        )
        static let appSheetGradientBottom = adaptive(
            light: UIColor.secondarySystemBackground,
            dark: .black
        )
        static let appGlassFill = adaptive(
            light: UIColor.white.withAlphaComponent(0.78),
            dark: UIColor.white.withAlphaComponent(0.12)
        )
        static let appGlassFillStrong = adaptive(
            light: UIColor.white.withAlphaComponent(0.95),
            dark: UIColor.white.withAlphaComponent(0.18)
        )
        static let appGlassForeground = adaptive(
            light: UIColor.label.withAlphaComponent(0.85),
            dark: UIColor.white.withAlphaComponent(0.85)
        )
        static let appControlActiveFill = adaptive(
            light: UIColor.label,
            dark: .white
        )
        static let appControlActiveForeground = adaptive(
            light: .white,
            dark: .black
        )
        static let appControlInactiveFill = adaptive(
            light: UIColor.black.withAlphaComponent(0.08),
            dark: UIColor.white.withAlphaComponent(0.16)
        )
        static let appArtworkOverlay = adaptive(
            light: UIColor.white.withAlphaComponent(0.45),
            dark: UIColor.black.withAlphaComponent(0.40)
        )
        static let appDivider = adaptive(
            light: UIColor.separator.withAlphaComponent(0.42),
            dark: UIColor.white.withAlphaComponent(0.11)
        )
        static let appShadow = adaptive(
            light: UIColor.black.withAlphaComponent(0.16),
            dark: UIColor.black.withAlphaComponent(0.36)
        )
        static let appHeroShadowIdle = adaptive(
            light: UIColor.black.withAlphaComponent(0.14),
            dark: UIColor.black.withAlphaComponent(0.22)
        )
        static let appHeroShadowPlaying = adaptive(
            light: UIColor.black.withAlphaComponent(0.20),
            dark: UIColor.black.withAlphaComponent(0.45)
        )
        static let appAmbientWash = adaptive(
            light: UIColor.white.withAlphaComponent(0.24),
            dark: UIColor.black.withAlphaComponent(0.28)
        )
        static let appAmbientVignetteTop = adaptive(
            light: UIColor.white.withAlphaComponent(0.34),
            dark: UIColor.black.withAlphaComponent(0.52)
        )
        static let appAmbientVignetteMid = adaptive(
            light: UIColor.white.withAlphaComponent(0.10),
            dark: UIColor.black.withAlphaComponent(0.18)
        )
        static let appAmbientVignetteBottom = adaptive(
            light: UIColor.white.withAlphaComponent(0.40),
            dark: UIColor.black.withAlphaComponent(0.58)
        )
        static let appAmbientRadial = adaptive(
            light: UIColor.white.withAlphaComponent(0.08),
            dark: UIColor.black.withAlphaComponent(0.14)
        )
        static let appFavoritesTileBackground = adaptive(
            light: UIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1),
            dark: UIColor.secondarySystemBackground
        )
        static let appPlaceholderPrimary = adaptive(
            light: UIColor(red: 0.86, green: 0.87, blue: 0.90, alpha: 1),
            dark: UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        )
        static let appPlaceholderSecondary = adaptive(
            light: UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1),
            dark: UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
        )
        static let appPlaceholderTertiary = adaptive(
            light: UIColor(red: 0.78, green: 0.78, blue: 0.82, alpha: 1),
            dark: UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
        )
        static let appPlaceholderQuaternary = adaptive(
            light: UIColor(red: 0.72, green: 0.72, blue: 0.76, alpha: 1),
            dark: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        )
        static let appPlaceholderSheen = adaptive(
            light: UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 0.18),
            dark: UIColor(red: 0.28, green: 0.28, blue: 0.32, alpha: 0.36)
        )
        static let appPlaceholderSheenSoft = adaptive(
            light: UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 0.10),
            dark: UIColor(red: 0.24, green: 0.24, blue: 0.28, alpha: 0.22)
        )
        static let appToolbarPillBackground = adaptive(
            light: UIColor.black.withAlphaComponent(0.82),
            dark: UIColor.white.withAlphaComponent(0.12)
        )
        static let appToolbarAvatarBackground = adaptive(
            light: UIColor.black.withAlphaComponent(0.72),
            dark: UIColor.white.withAlphaComponent(0.12)
        )
    #endif
}

enum AM {
    enum Radius {
        static let thumb: CGFloat = 7
        static let card: CGFloat = 8
        static let hero: CGFloat = 10
        static let tile: CGFloat = 8
        static let popup: CGFloat = 6
        static let sheet: CGFloat = 16
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let screenMargin: CGFloat = 16
        static let shelfSpacing: CGFloat = 20
        static let shelfTile: CGFloat = 162
        static let compactShelfTile: CGFloat = 132
        static let tabBarContentInset: CGFloat = 32
        static let sidebarContentInset: CGFloat = 32
    }

    enum Layout {
        static let wideContentMaxWidth: CGFloat = 1180
        static let wideRailMaxWidth: CGFloat = 740
        static let wideInspectorWidth: CGFloat = 340

        static func usesWideCanvas(
            horizontalSizeClass: UserInterfaceSizeClass?,
            availableWidth: CGFloat? = nil
        ) -> Bool {
            guard horizontalSizeClass == .regular else { return false }
            #if canImport(UIKit)
                if UIDevice.current.userInterfaceIdiom == .mac {
                    return true
                }
            #endif
            guard let availableWidth else { return false }
            return availableWidth >= 1050
        }

        static func shelfTileWidth(for availableWidth: CGFloat, compact: Bool = false) -> CGFloat {
            let sidePadding = Spacing.screenMargin * 2
            let visibleItems: CGFloat = if availableWidth >= 900 {
                compact ? 5.4 : 4.6
            } else if availableWidth >= 700 {
                compact ? 4.4 : 3.6
            } else if availableWidth <= 360 {
                compact ? 2.35 : 1.92
            } else {
                compact ? 2.85 : 2.22
            }
            let spacing = Spacing.l * max(visibleItems - 1, 0)
            let rawWidth = (availableWidth - sidePadding - spacing) / visibleItems
            let minimum = compact ? 118.0 : 148.0
            let maximum = compact ? 152.0 : 190.0
            return min(max(rawWidth, minimum), maximum)
        }

        static func playlistShelfTileWidth(for availableWidth: CGFloat) -> CGFloat {
            min(max(availableWidth * 0.42, 148), Spacing.shelfTile)
        }

        static func adaptiveGridColumns(
            minimum: CGFloat,
            spacing: CGFloat = Spacing.l
        ) -> [GridItem] {
            [
                GridItem(
                    .adaptive(minimum: minimum, maximum: minimum + 72),
                    spacing: spacing,
                    alignment: .top
                ),
            ]
        }

        static let playlistGridColumns = adaptiveGridColumns(minimum: 156)
        static let songGridColumns = adaptiveGridColumns(minimum: 154)
        static let categoryGridColumns = adaptiveGridColumns(minimum: 160, spacing: Spacing.m)

        static func mediaShelfHeight(tileWidth: CGFloat) -> CGFloat {
            tileWidth + 100
        }

        static func compactMediaShelfHeight(tileWidth: CGFloat) -> CGFloat {
            tileWidth + 86
        }

        static let mediaShelfHeight = mediaShelfHeight(tileWidth: 190)
        static let compactMediaShelfHeight = compactMediaShelfHeight(tileWidth: 152)
    }

    enum Font {
        static let sectionHeader = SwiftUI.Font.title.bold()
        static let groupHeader = SwiftUI.Font.headline.bold()
        static let tileTitle = SwiftUI.Font.headline
        static let tileCaption = SwiftUI.Font.caption
        static let rowTitle = SwiftUI.Font.body
        static let rowSubtitle = SwiftUI.Font.subheadline
        static let nowPlayingTitle = SwiftUI.Font.title.bold()
        static let nowPlayingArtist = SwiftUI.Font.headline
        static let timecode = SwiftUI.Font.caption.monospacedDigit()
        static let chevron = SwiftUI.Font.headline.bold()
    }

    enum Shadow {
        static let card = ShadowStyle(color: .appShadow, radius: 12, y: 5)
        static let heroIdle = ShadowStyle(color: .appHeroShadowIdle, radius: 16, y: 10)
        static let heroPlaying = ShadowStyle(color: .appHeroShadowPlaying, radius: 28, y: 18)
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }
}

extension View {
    func amShadow(_ style: AM.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }

    func musicScreenBackground() -> some View {
        background(ScreenBackgroundFill(style: .standard))
    }

    /// Same as `musicScreenBackground()` but matches `.insetGrouped` List
    /// screens (Settings, Account, Notifications) that otherwise paint
    /// `Color.appGroupedBackground` directly.
    func groupedScreenBackground() -> some View {
        background(ScreenBackgroundFill(style: .grouped))
    }

    func tabBarScrollInset() -> some View {
        modifier(TabBarScrollInsetModifier())
    }

    func tabBarBottomPadding() -> some View {
        modifier(TabBarBottomPaddingModifier())
    }
}

@MainActor
@discardableResult
func withOptionalAnimation<Result>(
    _ animation: Animation?,
    _ body: () throws -> Result
) rethrows -> Result {
    if let animation {
        return try withAnimation(animation) {
            try body()
        }
    } else {
        return try body()
    }
}

private enum AdaptiveBottomChrome {
    static func inset(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if canImport(UIKit)
            if horizontalSizeClass == .regular {
                let idiom = UIDevice.current.userInterfaceIdiom
                if idiom == .pad || idiom == .mac {
                    return AM.Spacing.sidebarContentInset
                }
            }
        #endif
        return AM.Spacing.tabBarContentInset
    }
}

private struct TabBarScrollInsetModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.contentMargins(
            .bottom,
            AdaptiveBottomChrome.inset(horizontalSizeClass: horizontalSizeClass),
            for: .scrollContent
        )
    }
}

private struct TabBarBottomPaddingModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.padding(
            .bottom,
            AdaptiveBottomChrome.inset(horizontalSizeClass: horizontalSizeClass)
        )
    }
}

struct AccountToolbarButton: View {
    @AppStorage("nk.username") private var username: String = ""
    @AppStorage("nk.avatar") private var avatarUrl: String = ""

    var body: some View {
        NavigationLink {
            AccountView()
        } label: {
            if let url = avatarURL {
                ToolbarAvatarLabel(url: url)
            } else {
                ToolbarIconLabel(systemImage: "person.fill")
            }
        }
        // Note this may not fire: SwiftUI substitutes its own button style
        // inside a `ToolbarItem` and discards the custom style's feedback with
        // it. Declared anyway because it costs nothing and works wherever the
        // style *is* honoured — a tap gesture here would be worse, since one
        // attached to a NavigationLink can win arbitration and eat the
        // navigation entirely.
        .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
        .accessibilityIdentifier("AccountToolbarButton")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens account and settings.")
    }

    private var avatarURL: URL? {
        let trimmed = avatarUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var displayName: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var accessibilityLabel: String {
        displayName.isEmpty ? "Account" : "Account, \(displayName)"
    }
}

struct ToolbarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var foregroundColor: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolbarIconLabel(systemImage: systemImage, foregroundColor: foregroundColor)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ToolbarCapsuleMenu<Content: View>: View {
    let accessibilityLabel: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            ToolbarIconLabel(systemImage: "ellipsis")
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ToolbarAvatarLabel: View {
    let url: URL

    var body: some View {
        if #available(iOS 26.0, *) {
            avatarImage(diameter: 30)
        } else {
            ZStack {
                ToolbarControlBackground()
                avatarImage(diameter: 32)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
    }

    private func avatarImage(diameter: CGFloat) -> some View {
        WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: "person.fill")
                .font(.headline)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }
}

private struct ToolbarIconLabel: View {
    let systemImage: String
    var foregroundColor: Color = .primary
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if #available(iOS 26.0, *) {
            iconImage
        } else {
            ZStack {
                ToolbarControlBackground()
                iconImage
                    .offset(x: iconHorizontalOffset)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
    }

    private var iconImage: some View {
        Image(systemName: systemImage)
            .font(.headline)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isEnabled ? foregroundColor : .secondary)
    }

    private var iconHorizontalOffset: CGFloat {
        0
    }
}

private struct ToolbarControlBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var backgroundStyle: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.appSecondaryBackground) : AnyShapeStyle(Material.regular)
    }

    var body: some View {
        Circle()
            .fill(backgroundStyle)
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: sheenColor, location: 0),
                                .init(color: .clear, location: 0.55),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [rimHighlight, rimShadow],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: shadowColor, radius: 3, x: 0, y: 1)
            .padding(4)
    }

    private var sheenColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.55)
    }

    private var rimHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.90)
    }

    private var rimShadow: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.06)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(0.10)
    }
}

struct AMSectionHeader<Destination: View>: View {
    let title: String
    let destination: Destination?
    init(_ title: String, destination: Destination) {
        self.title = title
        self.destination = destination
    }

    init(_ title: String) where Destination == EmptyView {
        self.title = title
        destination = nil
    }

    var body: some View {
        Group {
            if let destination {
                NavigationLink(destination: destination) {
                    headerRow(showChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                headerRow(showChevron: false)
            }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
    }

    private func headerRow(showChevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.s) {
            Text(title)
                .font(AM.Font.sectionHeader)
                .foregroundStyle(.primary)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.headline.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 2)
        .contentShape(Rectangle())
    }
}

struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledSystemFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}
