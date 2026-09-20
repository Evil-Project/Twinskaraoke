import SwiftUI
struct AppGlassBackground<S: Shape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Color.appSecondaryBackground))
                .overlay {
                    if contrast == .increased {
                        shape.stroke(Color.appDivider, lineWidth: 1)
                    }
                }
        } else {
            content.glassEffect(in: shape)
        }
    }
}

extension View {
    func appGlassBackground(in shape: some Shape) -> some View {
        modifier(AppGlassBackground(shape: shape))
    }
}

struct GlassCircle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Circle().fill(Color.appSecondaryBackground))
                .overlay(Circle().stroke(Color.appDivider, lineWidth: contrast == .increased ? 1 : 0.5))
                .clipShape(Circle())
                .contentShape(Circle())
        } else {
            content
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay {
                    if contrast == .increased {
                        Circle().stroke(Color.appDivider, lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
    }
}

struct GlassRoundedRect: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .appGlassBackground(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .appShadow, radius: 14, y: 6)
    }
}

struct GlassXButton: View {
    private static let defaultIconSize: CGFloat = 16

    var action: () -> Void
    var size: CGFloat = 44
    var accessibilityLabel = String(localized: "Close")

    var body: some View {
        Button(action: action) {
            Label(accessibilityLabel, systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.system(size: Self.defaultIconSize, weight: .semibold))
                .foregroundStyle(Color.appGlassForeground)
                .frame(width: size, height: size)
                .modifier(GlassCircle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        .buttonBorderShape(.circle)
    }
}

struct GlassCheckmarkButton: View {
    private static let defaultIconSize: CGFloat = 16

    var action: () -> Void
    var size: CGFloat = 44
    var isEnabled: Bool = true
    var accessibilityLabel = String(localized: "Done")

    var body: some View {
        Button(action: action) {
            Label(accessibilityLabel, systemImage: "checkmark")
                .labelStyle(.iconOnly)
                .font(.system(size: Self.defaultIconSize, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.appGlassForeground : .secondary)
                .frame(width: size, height: size)
                .modifier(GlassCircle())
                .contentShape(Circle())
        }
        .disabled(!isEnabled)
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        .buttonBorderShape(.circle)
    }
}

struct GlassActionButton: View {
    private static let defaultIconSize: CGFloat = 16

    var action: () -> Void
    var systemImage: String
    var size: CGFloat = 44
    var foregroundColor: Color = Color.appGlassForeground
    var isLoading: Bool = false
    var accessibilityLabel: String

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: size, height: size)
                .modifier(GlassCircle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        .buttonBorderShape(.circle)
    }

    @ViewBuilder
    private var icon: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(foregroundColor)
        } else {
            Label(accessibilityLabel, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: Self.defaultIconSize, weight: .semibold))
                .foregroundStyle(foregroundColor)
        }
    }
}
