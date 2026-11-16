import SwiftUI

struct BandleLeaderboardView: View {
    let model: BandleLeaderboardViewModel
    let onSelectPeriod: (BandleLeaderboardPeriod) -> Void

    var body: some View {
        VStack(spacing: AM.Spacing.l) {
            BandleSegmentPicker(
                title: String(localized: "Leaderboard period"),
                options: BandleLeaderboardPeriod.allCases,
                selection: model.period,
                isDisabled: model.isLoading,
                optionTitle: \.title,
                onSelect: onSelectPeriod
            )
            .accessibilityIdentifier("Bandle.PeriodPicker")

            if let rank = model.currentUserRank {
                Label(String(localized: "Your \(model.period.title) rank: \(rank)"), systemImage: "person.crop.circle.badge.checkmark")
                    .font(AM.Font.groupHeader)
                    .padding(AM.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
                    .accessibilityIdentifier("Bandle.YourRank")
            }

            if let board = model.leaderboard {
                if board.isInvalid == true {
                    Label(board.invalidationMessage ?? String(localized: "Daily Challenge Invalidated"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.period == .today {
                    BandleDailySummary(board: board)
                }

                if let values = board.attemptDistribution {
                    BandleAttemptDistribution(values: values, title: String(localized: "Guess Distribution"))
                }

                if let entries = board.entries, !entries.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            VStack(spacing: 0) {
                                BandleLeaderboardRow(entry: entry, period: model.period)
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, AM.Spacing.l)
                    .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
                } else {
                    ContentUnavailableView(
                        String(localized: "No entries yet"),
                        systemImage: "list.number",
                        description: Text(String(localized: "Completed ranked games will appear here."))
                    )
                    .accessibilityIdentifier("Bandle.Leaderboard.Empty")
                }

                if let total = board.totalPlaysIncludingGuests, let ranked = board.totalPlayers, total > ranked {
                    Text(String(localized: "Guest plays not shown on leaderboard: \(total - ranked)"))
                        .font(AM.Font.rowCompactSubtitle)
                        .foregroundStyle(.secondary)
                }
            } else if model.isLoading {
                ProgressView(String(localized: "Loading leaderboard..."))
                    .accessibilityIdentifier("Bandle.Leaderboard.Loading")
            }
        }
    }
}
