import SwiftUI

struct VerticalKaraokeLevel: View {
    @Binding var value: Double
    var enabled: Bool = true
    var onSet: (Double) -> Void = { _ in }

    var body: some View {
        GeometryReader { geometry in
            NativeLevelSlider(value: $value, onSet: onSet)
                .tint(Color.primary.opacity(enabled ? 1 : 0.4))
                // Increasing volume always moves upward, including RTL layouts.
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: geometry.size.height, height: geometry.size.width)
                .rotationEffect(.degrees(-90))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}
