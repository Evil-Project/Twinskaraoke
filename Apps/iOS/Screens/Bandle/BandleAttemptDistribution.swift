import SwiftUI

struct BandleAttemptDistribution: View {
    let values: [String: Int]
    let title: String

    private var maximum: Int {
        max(values.values.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.m) {
            Text(title)
                .font(AM.Font.groupHeader)
            // Every label is "Attempt n" with a single digit, so monospaced
            // digits keep the bars aligned without a fixed label width.
            ForEach(1 ... 6, id: \.self) { attempt in
                let count = values[String(attempt)] ?? 0
                HStack(spacing: AM.Spacing.m) {
                    Text(String(localized: "Attempt \(attempt)"))
                        .font(AM.Font.rowCompactSubtitle.monospacedDigit())
                        .fixedSize()
                    ProgressView(value: Double(count), total: Double(maximum))
                        .tint(Color.appAccent)
                        .accessibilityHidden(true)
                    Text(count, format: .number)
                        .font(AM.Font.rowCompactTitle.bold().monospacedDigit())
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Attempt \(attempt): \(count)"))
            }
        }
        .padding(AM.Spacing.l)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
        .accessibilityIdentifier("Bandle.AttemptDistribution")
    }
}
