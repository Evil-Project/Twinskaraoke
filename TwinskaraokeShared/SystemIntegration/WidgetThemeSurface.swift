#if os(iOS)
import SwiftUI
import WidgetKit

struct WidgetVisualTheme {
    var variant: SharedThemeVariant
    var fullColor = true
    var backdrop: SharedThemeDefinition.Backdrop = .solid
    var text: Color { fullColor ? variant[.text].color : .primary }
    var secondaryText: Color { fullColor ? variant[.secondaryText].color : .secondary }
    var accent: Color { fullColor ? variant.readableAccent(backdrop: backdrop).color : .primary }
    var paletteAccent: Color { fullColor ? variant[.accent].color : .secondary }
    var controlFill: Color { fullColor ? variant[.playerActionFill].color : .primary.opacity(0.12) }
    var divider: Color { fullColor ? variant[.appDivider].color : .secondary.opacity(0.3) }
    var surface: Color { fullColor ? variant[.secondaryBackground].color : .secondary.opacity(0.12) }
}
private struct WidgetVisualThemeKey: EnvironmentKey {
    static let defaultValue = WidgetVisualTheme(variant: SharedThemeDefinition.builtIn(.dark).dark)
}
extension EnvironmentValues {
    var widgetVisualTheme: WidgetVisualTheme {
        get { self[WidgetVisualThemeKey.self] }
        set { self[WidgetVisualThemeKey.self] = newValue }
    }
}

/// The container owns system corner treatment. All relief stays inside its
/// drawable area; no outside shadow, animation, or thick decorative frame.
struct WidgetThemeSurface: View {
    let theme: SharedThemeDefinition
    let variant: SharedThemeVariant
    var fullColor = true
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if fullColor { variant[.background].color }
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            ContainerRelativeShape()
                .strokeBorder(shade, lineWidth: variant.edgeWidth)
                .shadow(color: shade, radius: variant.shadowRadius, x: 0, y: 2)
                .padding(variant.surfaceInset)
            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(colors: [highlight, .clear, shade], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: variant.edgeWidth
                )
                .padding(0.5)
            ContainerRelativeShape()
                .strokeBorder(fullColor ? variant[.insetHighlight].color : .primary.opacity(0.08), lineWidth: 0.5)
                .padding(variant.surfaceInset + 1)
        }
        .clipShape(ContainerRelativeShape())
        .accessibilityHidden(true)
    }
    private var colors: [Color] {
        guard fullColor else { return [.clear, .clear] }
        if theme.backdrop == .aurora {
            if differentiate { return [variant[.plainBackdrop].color, variant[.plainBackdrop].color] }
            if reduceTransparency { return [variant[.cloudTopLeading].color, variant[.cloudTopTrailing].color] }
            return [variant[.cloudTopLeading].color, variant[.cloudBottomTrailing].color, variant[.cloudTopTrailing].color]
        }
        return [variant[.surfaceTop].color, variant[.surfaceBottom].color]
    }
    private var highlight: Color { fullColor ? variant[.edgeHighlight].color : .primary.opacity(0.12) }
    private var shade: Color { fullColor ? variant[.edgeShade].color : .primary.opacity(0.08) }
}

struct WidgetThemedView<Content: View>: View {
    let theme: SharedThemeDefinition
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        let fullColor = renderingMode == .fullColor
        let variant = theme.variant(for: scheme)
        let visual = WidgetVisualTheme(variant: variant, fullColor: fullColor, backdrop: theme.backdrop)
        content()
            .environment(\.widgetVisualTheme, visual)
            .foregroundStyle(visual.text)
            .tint(visual.accent)
            .fontDesign(variant.design)
            // Widget bounds cannot grow with accessibility text. Keep larger
            // supported text, while VoiceOver exposes complete metadata.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .environment(\.colorScheme, fullColor ? (theme.colorScheme ?? scheme) : scheme)
            .containerBackground(for: .widget) {
                WidgetThemeSurface(theme: theme, variant: variant, fullColor: fullColor)
            }
    }
}
#endif
