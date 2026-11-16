import SwiftUI

struct BandlePersonalSummary: View {
    let userData: BandleUserData?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AM.Spacing.xl) {
                streak
                played
                winRate
            }
            VStack(spacing: AM.Spacing.l) {
                streak
                played
                winRate
            }
        }
        .padding(AM.Spacing.l)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
        .accessibilityIdentifier("Bandle.PersonalSummary")
    }

    private var streak: BandleSummaryValue {
        BandleSummaryValue(value: Text(userData?.streak ?? 0, format: .number), label: String(localized: "Streak"))
    }

    private var played: BandleSummaryValue {
        BandleSummaryValue(value: Text(userData?.gamesPlayed ?? 0, format: .number), label: String(localized: "Played"))
    }

    private var winRate: BandleSummaryValue {
        BandleSummaryValue(
            value: Text((userData?.winPercentage ?? 0) / 100, format: .percent.precision(.fractionLength(0))),
            label: String(localized: "Win Rate")
        )
    }
}
