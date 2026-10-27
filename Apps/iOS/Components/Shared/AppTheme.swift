import SDWebImageSwiftUI
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

extension AppearanceMode {
    var palette: AppThemePalette? {
        let definition = SharedThemeDefinition.builtIn(self)
        return definition.usesPalette ? AppThemePalette(definition: definition) : nil
    }
}

/// A screen surface driven by the observed shared theme. Aurora themes draw
/// an opaque backdrop in each screen so navigation transitions composite
/// normally; other themes use the standard or grouped background token.
struct ScreenBackgroundFill: View {
    enum Style {
        case standard
        case grouped
    }

    var style: Style = .standard

    private var isNwero: Bool {
        AppThemeStore.shared.definition.backdrop == .aurora
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
    private static let systemDefinition = SharedThemeDefinition.builtIn(.system)

    private static func adaptive(_ token: ThemeToken) -> Color {
        Color(uiColor: UIColor { trait in
            let variant = systemDefinition.variant(for: trait.userInterfaceStyle == .dark ? .dark : .light)
            let rgba = variant[token]
            return UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        })
    }
    static let standardBackground = adaptive(.standardBackground)
    static let standardSecondaryBackground = adaptive(.standardSecondaryBackground)
    static let standardGroupedBackground = adaptive(.standardGroupedBackground)
    static let standardSheetGradientTop = adaptive(.standardSheetGradientTop)
    static let standardSheetGradientBottom = adaptive(.standardSheetGradientBottom)
    static let appGlassFill = adaptive(.appGlassFill)
    static let appGlassFillStrong = adaptive(.appGlassFillStrong)
    static let appGlassForeground = adaptive(.appGlassForeground)
    static let appControlActiveFill = adaptive(.appControlActiveFill)
    static let appControlActiveForeground = adaptive(.appControlActiveForeground)
    static let appControlInactiveFill = adaptive(.appControlInactiveFill)
    static let standardPlayerActionFill = adaptive(.standardPlayerActionFill)
    static let appArtworkOverlay = adaptive(.appArtworkOverlay)
    static let appDivider = adaptive(.appDivider)
    static let appShadow = adaptive(.appShadow)
    static let appHeroShadowIdle = adaptive(.appHeroShadowIdle)
    static let appHeroShadowPlaying = adaptive(.appHeroShadowPlaying)
    static let appAmbientWash = adaptive(.appAmbientWash)
    static let appAmbientVignetteTop = adaptive(.appAmbientVignetteTop)
    static let appAmbientVignetteMid = adaptive(.appAmbientVignetteMid)
    static let appAmbientVignetteBottom = adaptive(.appAmbientVignetteBottom)
    static let appAmbientRadial = adaptive(.appAmbientRadial)
    static let appFavoritesTileBackground = adaptive(.appFavoritesTileBackground)
    static let appPlaceholderPrimary = adaptive(.appPlaceholderPrimary)
    static let appPlaceholderSecondary = adaptive(.appPlaceholderSecondary)
    static let appPlaceholderTertiary = adaptive(.appPlaceholderTertiary)
    static let appPlaceholderQuaternary = adaptive(.appPlaceholderQuaternary)
    static let appPlaceholderSheen = adaptive(.appPlaceholderSheen)
    static let appPlaceholderSheenSoft = adaptive(.appPlaceholderSheenSoft)
    static let appToolbarPillBackground = adaptive(.appToolbarPillBackground)
    static let appToolbarAvatarBackground = adaptive(.appToolbarAvatarBackground)

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

/// The inset-grouped `List` the settings-style screens share: Settings,
/// Account, About and the screens under them.
///
/// Its rows would otherwise draw on the system's grey, which sits wrong on a
/// website theme's tinted page, so those themes give rows their own
/// `--*-bg-secondary`. Every other theme passes `nil`, which keeps the system
/// row fill. The `Group` is what carries it: `listRowBackground` on the `List`
/// itself never reaches the rows, while a `Group` hands it to every section.
struct InsetGroupedList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        List {
            Group {
                content
            }
            .listRowBackground(AppThemeStore.shared.palette?.secondaryBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }
}

extension View {
    /// Reports this view's width into `width`, ignoring sub-point jitter.
    ///
    /// Shelves need their own width in two places at once: inside a
    /// `GeometryReader` to size tiles, and outside it to size the fixed frame
    /// the `GeometryReader` sits in. The proxy only reaches the first, so the
    /// width has to be carried out in state. Five shelves were each about to
    /// grow their own copy of that.
    func trackingWidth(into width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            guard newWidth > 0, abs(newWidth - width.wrappedValue) > 0.5 else { return }
            width.wrappedValue = newWidth
        }
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
            // Every tab root carries this button. Built eagerly, each toolbar
            // pass minted an AuthManager, which reads the session and
            // registers three notification observers, only to discard it.
            DeferredView { AccountView() }
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
        displayName.isEmpty ? String(localized: "Account") : String(localized: "Account, \(displayName)")
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
