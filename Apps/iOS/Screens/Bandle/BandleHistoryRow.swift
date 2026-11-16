import SwiftUI

struct BandleHistoryRow: View {
    let entry: BandleHistoryEntry

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: AM.Spacing.m) {
            Image(systemName: entry.won == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.won == true ? .green : .red)
                .accessibilityLabel(entry.won == true ? String(localized: "Won") : String(localized: "Lost"))

            VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                Text(entry.dailySong?.songTitle ?? String(localized: "Daily Challenge"))
                    .font(AM.Font.rowTitle)
                if let day = entry.challengeDay, let date = calendar.date(from: day) {
                    Text(date, format: .dateTime.day().month().year().locale(locale))
                        .font(AM.Font.rowCompactSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: AM.Spacing.xs) {
                Text(String(localized: "Attempt \(entry.attemptNumber ?? 0)/6"))
                    .font(AM.Font.rowCompactTitle.bold())
                Text(entry.score ?? 0, format: .number)
                    .font(AM.Font.rowCompactSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AM.Spacing.s)
        .accessibilityIdentifier("Bandle.History.Entry.\(entry.id)")
    }
}
