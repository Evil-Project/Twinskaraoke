import SwiftUI

struct BandleDailySummary: View {
    let board: BandleLeaderboard

    var body: some View {
        VStack(spacing: AM.Spacing.m) {
            LabeledContent(String(localized: "Players")) {
                Text(board.totalPlayers ?? 0, format: .number)
            }
            LabeledContent(String(localized: "Wins")) {
                Text(board.totalWins ?? 0, format: .number)
            }
            LabeledContent(String(localized: "Losses")) {
                Text(board.totalLosses ?? 0, format: .number)
            }
            LabeledContent(String(localized: "Average Attempt")) {
                Text(board.averageAttempt ?? 0, format: .number.precision(.fractionLength(1)))
            }
            LabeledContent(String(localized: "Perfect Scores")) {
                Text(board.perfectScoreCount ?? 0, format: .number)
            }
        }
        .padding(AM.Spacing.l)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
        .accessibilityIdentifier("Bandle.DailySummary")
    }
}
