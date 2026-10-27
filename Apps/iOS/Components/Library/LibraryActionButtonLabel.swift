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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(Color.appAccent)
        .background(Color.appControlInactiveFill, in: shape)
        .shadow(color: Color.appShadow.opacity(0.18), radius: 5, x: 0, y: 2)
        .contentShape(shape)
    }
}
