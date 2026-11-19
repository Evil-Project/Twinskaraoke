import SwiftUI

/// A count followed by its share of all plays, as in "35  95%".
struct BandleCountWithRate: View {
    let count: Int?
    let rate: Double?

    var body: some View {
        HStack(spacing: AM.Spacing.s) {
            Text(count ?? 0, format: .number)
            if let rate {
                Text(rate, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
