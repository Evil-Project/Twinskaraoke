import SwiftUI

// MARK: - Glass Modifiers

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
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay {
                    if contrast == .increased {
                        Circle().stroke(Color.appDivider, lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        } else {
            content
                .background(
                    Circle()
                        .fill(Color.appGlassFill)
                )
                .overlay(
                    Circle()
                        .stroke(Color.appDivider.opacity(contrast == .increased ? 1 : 0.7), lineWidth: contrast == .increased ? 1 : 0.5)
                )
                .clipShape(Circle())
                .contentShape(Circle())
        }
    }
}

struct GlassRoundedRect: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(shape.fill(Color.appSecondaryBackground))
                .overlay {
                    if contrast == .increased {
                        shape.stroke(Color.appDivider, lineWidth: 1)
                    }
                }
                .shadow(color: .appShadow, radius: 14, y: 6)
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(in: shape)
                .shadow(color: .appShadow, radius: 14, y: 6)
        } else {
            content
                .background(
                    shape.fill(Color.appGlassFill)
                )
                .shadow(color: .appShadow, radius: 14, y: 6)
        }
    }
}

// MARK: - Glass Buttons

struct GlassXButton: View {
    private static let defaultIconSize: CGFloat = 16

    var action: () -> Void
    var size: CGFloat = 44
    var accessibilityLabel = "Close"

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
    var accessibilityLabel = "Done"

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
