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
        /// The circle under the player's round actions — favorite, more, the
        /// lyrics-header chevron and the queue-mode badge. A shade deeper than
        /// `appControlInactiveFill`, which washed out against the artwork
        /// ambience; Apple Music's reads as a darker grey than the surface it
        /// sits on rather than a light film over it.
        static let appPlayerActionFill = adaptive(
            light: UIColor.black.withAlphaComponent(0.12),
            dark: UIColor.white.withAlphaComponent(0.10)
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
    /// Continuous corner radii, ramped by element size the way Apple Music's
    /// are. A 44pt row thumbnail and a 340pt player hero should not share a
    /// corner, which is what the old flat 7/8/10 ramp gave them.
    enum Radius {
        static let thumb: CGFloat = 6
        static let card: CGFloat = 10
        static let tile: CGFloat = 10
        /// Large artwork surfaces: the full-screen player, the radio and wide
        /// heroes, playlist and browse headers.
        ///
        /// `ArtworkMorphLayer` lerps `thumb -> hero` while `PlayerArtworkView`
        /// draws at `hero`, so the flying artwork lands on exactly the corner
        /// it turns into. Those two must keep reading the same token — split
        /// this in half and the morph ends on a different shape than the
        /// artwork underneath it.
        static let hero: CGFloat = 16
        static let popup: CGFloat = 6
        static let sheet: CGFloat = 20
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
        /// A section header to the content it labels. One value for every
        /// shelf and grid, so the rhythm does not drift per section.
        static let sectionHeaderGap: CGFloat = 10
        static let shelfTile: CGFloat = 162
        static let compactShelfTile: CGFloat = 132
    }

    enum Layout {
        static let wideContentMaxWidth: CGFloat = 1180
        static let wideRailMaxWidth: CGFloat = 740
        static let wideInspectorWidth: CGFloat = 340
        /// A 13-inch iPad is 1376pt wide in landscape. Its balanced sidebar
        /// consumes 330pt, leaving a 1046pt detail canvas; using the former
        /// 1050pt threshold for both shell and content meant the largest iPad
        /// opened a sidebar and then missed every wide content layout by 4pt.
        static let wideCanvasMinimumWidth: CGFloat = 980
        static let sidebarMinimumWidth: CGFloat = 1050

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
            return availableWidth >= wideCanvasMinimumWidth
        }

        static func usesSidebarCanvas(
            horizontalSizeClass: UserInterfaceSizeClass?,
            availableWidth: CGFloat
        ) -> Bool {
            guard horizontalSizeClass == .regular else { return false }
            #if canImport(UIKit)
                // Mac idiom windows keep desktop navigation even when resized
                // below the iPad sidebar threshold. Falling back to a tab bar
                // here is a platform regression, not an adaptive layout.
                if UIDevice.current.userInterfaceIdiom == .mac {
                    return true
                }
            #endif
            return availableWidth >= sidebarMinimumWidth
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

        /// Everything a shelf needs above and below its artwork: the section
        /// header, the gap under it, and the tile's two label lines.
        ///
        /// At the default text size this is 90 — retuned from 100 when the type
        /// ramp moved, since the header dropped 28pt to 22pt and the tile labels
        /// from headline+caption to a matched subheadline pair.
        ///
        /// Shelves scale it with `@ScaledMetric`. A shelf's height is fixed
        /// because it lives in a `GeometryReader`, so nothing else can grow it,
        /// and at Accessibility L the labels need roughly half again this much —
        /// a bare constant clipped tile titles through the baseline and dropped
        /// the caption line entirely.
        static let shelfLabelAllowance: CGFloat = 90

        static func mediaShelfHeight(tileWidth: CGFloat, labelAllowance: CGFloat = shelfLabelAllowance) -> CGFloat {
            tileWidth + labelAllowance
        }

        static func compactMediaShelfHeight(tileWidth: CGFloat) -> CGFloat {
            tileWidth + 86
        }

        static let mediaShelfHeight = mediaShelfHeight(tileWidth: 190)
        static let compactMediaShelfHeight = compactMediaShelfHeight(tileWidth: 152)
    }

    /// The type ramp, calibrated against Apple Music rather than assembled a
    /// call site at a time. Pick by role — the sizes and weights *are* the
    /// design, and a raw `.font(.headline)` next to one of these is how the
    /// interface drifts.
    enum Font {
        /// A heading that carries a whole screen, below the navigation title.
        static let screenTitle = SwiftUI.Font.largeTitle.bold()
        /// Shelf and section headings: "Recently Added", "Made For You".
        /// 22pt, not the 28pt `.title` this used to be — Apple Music's shelf
        /// headers sit close to the content they label.
        static let sectionHeader = SwiftUI.Font.title2.bold()
        /// The title on a featured card that is smaller than the full-width
        /// hero — the radio's featured episode, a promoted playlist.
        static let heroTitle = SwiftUI.Font.title.bold()
        /// The small uppercase kicker over a hero or featured title.
        /// Always paired with `.textCase(.uppercase)` and a secondary colour.
        static let eyebrow = SwiftUI.Font.caption.weight(.semibold)
        /// One level under `sectionHeader`.
        static let groupHeader = SwiftUI.Font.title3.weight(.semibold)

        /// Tile title and caption are the *same size* and separate on colour
        /// alone. That is what makes an Apple Music shelf read as a grid of
        /// items rather than a grid of headlines with footnotes under them.
        static let tileTitle = SwiftUI.Font.subheadline
        static let tileCaption = SwiftUI.Font.subheadline

        static let rowTitle = SwiftUI.Font.body
        static let rowSubtitle = SwiftUI.Font.subheadline
        static let rowCompactTitle = SwiftUI.Font.subheadline
        static let rowCompactSubtitle = SwiftUI.Font.footnote

        static let nowPlayingTitle = SwiftUI.Font.title2.bold()
        static let nowPlayingArtist = SwiftUI.Font.title3
        /// The player's title pair where the layout is tight — the iPad control
        /// bar, the lyrics header, and any phone geometry short enough that the
        /// full pair would crowd the transport.
        static let nowPlayingTitleCompact = SwiftUI.Font.headline.bold()
        static let nowPlayingArtistCompact = SwiftUI.Font.subheadline
        /// Glyphs on the player's round chrome buttons — favourite, more,
        /// the lyrics chevron, the translation globe.
        static let playerGlyph = SwiftUI.Font.headline.weight(.semibold)

        /// Counts and status pills.
        static let badge = SwiftUI.Font.caption2.weight(.semibold)
        static let timecode = SwiftUI.Font.caption.monospacedDigit()
        static let chevron = SwiftUI.Font.subheadline.weight(.semibold)
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

    /// Search on a screen whose subject is the list, not the searching: the
    /// field collapses to a toolbar button until tapped, so the content keeps
    /// the room.
    ///
    /// The Search tab deliberately does not use this. Its field stays expanded,
    /// because searching is the whole point of that screen.
    func secondarySearchBehavior() -> some View {
        searchToolbarBehavior(.minimize)
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
        avatarImage(diameter: 30)
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
        iconImage
    }

    private var iconImage: some View {
        Image(systemName: systemImage)
            .font(.headline)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isEnabled ? foregroundColor : .secondary)
    }
}

/// The one section header. Every shelf, grid and panel heading goes through
/// this — there used to be three hand-rolled variants that disagreed on the
/// chevron's size, weight and colour.
///
/// The chevron carries no hit frame of its own on purpose. The whole row is
/// the `NavigationLink`'s target via `contentShape`, so a 44x44 box around a
/// 17pt glyph would only inflate the header's height without widening
/// anything you can actually tap.
/// The one section header. Every shelf, grid and panel heading goes through
/// this — there used to be three hand-rolled variants that disagreed on the
/// chevron's size, weight and colour.
///
/// The title is an **already-localized** `String`: callers pass
/// `String(localized: "…")`. That is deliberate. This component cannot take a
/// `LocalizedStringKey` (shelves must hand the same text to a destination's
/// `navigationTitle`, and a key cannot be read back out) and
/// `LocalizedStringResource` was worse — verified on a clean build, literals
/// reaching a custom initializer that way are never extracted into the string
/// catalog at all, so the headings silently shipped as English. Resolving at
/// the call site is the form Xcode does extract.
///
/// The chevron carries no hit frame of its own on purpose. The whole row is
/// the `NavigationLink`'s target via `contentShape`, so a 44x44 box around a
/// 17pt glyph would only inflate the header's height without widening
/// anything you can actually tap.
struct AMSectionHeader<Destination: View>: View {
    let title: String
    let destination: Destination?
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin

    init(
        _ title: String,
        destination: Destination,
        horizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) {
        self.title = title
        self.destination = destination
        self.horizontalPadding = horizontalPadding
    }

    init(
        _ title: String,
        horizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) where Destination == EmptyView {
        self.title = title
        destination = nil
        self.horizontalPadding = horizontalPadding
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
        .padding(.horizontal, horizontalPadding)
    }

    private func headerRow(showChevron: Bool) -> some View {
        HStack(spacing: AM.Spacing.xs) {
            // `verbatim`: the string arrived translated, or is server data.
            // Either way there is nothing left to look up.
            Text(verbatim: title)
                .font(AM.Font.sectionHeader)
                .foregroundStyle(.primary)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(AM.Font.chevron)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
