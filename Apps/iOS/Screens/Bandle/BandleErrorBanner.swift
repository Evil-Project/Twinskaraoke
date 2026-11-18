import SwiftUI

struct BandleErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.m) {
            Label {
                Text(message)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.appDestructive)
            }
            .font(AM.Font.rowCompactTitle)
            .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Reload"), systemImage: "arrow.clockwise", action: onRetry)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("Bandle.Reload")
        }
        .padding(AM.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
    }
}
