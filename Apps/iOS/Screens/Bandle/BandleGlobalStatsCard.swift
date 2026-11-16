import SwiftUI

struct BandleGlobalStatsCard: View {
    let stats: BandleGlobalStats

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.m) {
            Text(String(localized: "Today's Global Stats"))
                .font(AM.Font.groupHeader)
            LabeledContent(String(localized: "Players")) {
                Text(stats.totalPlayers ?? 0, format: .number)
            }
            LabeledContent(String(localized: "Winners")) {
                Text(stats.totalWinners ?? 0, format: .number)
            }
            LabeledContent(String(localized: "Average Attempt")) {
                Text(stats.averageAttempt ?? 0, format: .number.precision(.fractionLength(1)))
            }
            LabeledContent(String(localized: "Perfect Scores")) {
                Text(stats.perfectScores ?? 0, format: .number)
            }
        }
        .padding(AM.Spacing.l)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
        .accessibilityIdentifier("Bandle.GlobalStats")
    }
}
