import SwiftUI

struct BandleDailySummary: View {
    let stats: BandleDailyStats

    var body: some View {
        VStack(spacing: AM.Spacing.m) {
            LabeledContent(String(localized: "Players")) {
                Text(stats.players ?? 0, format: .number)
            }
            LabeledContent(String(localized: "Wins")) {
                BandleCountWithRate(count: stats.wins, rate: stats.winRate)
            }
            LabeledContent(String(localized: "Losses")) {
                BandleCountWithRate(count: stats.losses, rate: stats.lossRate)
            }
            LabeledContent(String(localized: "Average Attempt")) {
                Text(stats.averageAttempt ?? 0, format: .number.precision(.fractionLength(1)))
            }
            if let time = stats.averageTime {
                LabeledContent(String(localized: "Average Time")) {
                    Text(time, format: .time(pattern: .minuteSecond(padMinuteToLength: 2)))
                }
            }
            LabeledContent(String(localized: "Perfect Scores")) {
                Text(stats.perfectScores ?? 0, format: .number)
            }
        }
        .padding(AM.Spacing.l)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
        .accessibilityIdentifier("Bandle.DailySummary")
    }
}
