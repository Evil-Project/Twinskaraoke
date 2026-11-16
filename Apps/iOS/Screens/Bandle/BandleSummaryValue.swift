import SwiftUI

struct BandleSummaryValue: View {
    let value: Text
    let label: String

    var body: some View {
        VStack(spacing: AM.Spacing.xs) {
            value
                .font(AM.Font.groupHeader)
                .foregroundStyle(Color.appAccent)
            Text(label)
                .font(AM.Font.tileCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
