import SwiftUI

struct LibraryActionButtonLabel: View {
    let symbol: String
    let text: String
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
            Text(text).fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(Color.appAccent)
        .background(Color.appControlInactiveFill, in: shape)
        .shadow(color: Color.appShadow.opacity(0.18), radius: 5, x: 0, y: 2)
        .contentShape(shape)
    }
}

/// Play and Shuffle, side by side.
///
/// At an accessibility text size they stack instead. Sharing a row there,
/// each button had half the width for a label several times its usual size,
/// and "Shuffle" broke in the middle of the word.
struct LibraryActionButtonRow<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: AM.Spacing.s))
            : AnyLayout(HStackLayout(spacing: AM.Spacing.m))
        layout { content }
    }
}
