import SwiftUI

struct BandleLeaderboardRow: View {
    let entry: BandleLeaderboardEntry
    let period: BandleLeaderboardPeriod

    @ScaledMetric(relativeTo: .body) private var avatarSize = 44
    @ScaledMetric(relativeTo: .title3) private var rankWidth = 36

    var body: some View {
        HStack(spacing: AM.Spacing.m) {
            Text(entry.rank ?? 0, format: .number)
                .font(AM.Font.groupHeader.monospacedDigit())
                .foregroundStyle(Color.appAccent)
                .frame(minWidth: rankWidth)
                .accessibilityLabel(String(localized: "Rank \(entry.rank ?? 0)"))

            BandleAvatar(url: entry.avatarURL)
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(.circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                HStack {
                    Text(entry.username ?? String(localized: "Unknown player"))
                        .font(AM.Font.rowTitle)
                        .foregroundStyle(.primary)
                    if entry.isPerfect == true {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(String(localized: "Perfect score"))
                    }
                }
                Text(detailText)
                    .font(AM.Font.rowCompactSubtitle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(score, format: .number)
                .font(AM.Font.rowCompactTitle.bold())
                .foregroundStyle(.primary)
                .accessibilityLabel(String(localized: "Score \(score)"))
        }
        .padding(.vertical, AM.Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Bandle.Leaderboard.Entry.\(entry.id)")
    }

    private var score: Int64 {
        entry.totalScore ?? Int64(entry.score ?? 0)
    }

    private var detailText: String {
        if period == .today {
            let attempt = entry.attemptNumber ?? 0
            guard let time = entry.timeSpent.flatMap(BandleTimeSpan.duration(from:)) else {
                return String(localized: "Attempt \(attempt)")
            }
            return String(localized: "Attempt \(attempt) · \(time.formatted(.time(pattern: .minuteSecond)))")
        }
        if let streak = entry.streak {
            return String(localized: "Games: \(entry.played ?? 0) · Streak: \(streak)")
        }
        return String(localized: "Games: \(entry.played ?? 0) · Wins: \(entry.won ?? 0)")
    }
}
