import SwiftUI

struct BandleStatsView: View {
    @State private var model = BandleLeaderboardViewModel()
    @State private var section = BandleStatsSection.leaderboard

    var body: some View {
        ScrollView {
            VStack(spacing: AM.Spacing.l) {
                if BandleMode.visibleModes.count > 1 {
                    BandleSegmentPicker(
                        title: String(localized: "Challenge mode"),
                        options: BandleMode.visibleModes,
                        selection: model.mode,
                        isDisabled: model.isLoading,
                        optionTitle: \.title,
                        onSelect: selectMode
                    )
                    .accessibilityIdentifier("Bandle.ModePicker")
                }
                BandlePersonalSummary(userData: model.userData)

                if let values = model.userData?.attemptDistribution {
                    BandleAttemptDistribution(values: values, title: String(localized: "Your Guess Distribution"))
                }

                if let message = model.errorMessage {
                    BandleErrorBanner(message: message, onRetry: retry)
                }

                Picker(String(localized: "Statistics section"), selection: $section) {
                    ForEach(BandleStatsSection.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("Bandle.StatsSection")

                switch section {
                case .leaderboard:
                    BandleLeaderboardView(model: model, onSelectPeriod: selectPeriod)
                case .history:
                    if model.isLoading, model.history.isEmpty {
                        ProgressView()
                            .accessibilityIdentifier("Bandle.Stats.Loading")
                    } else {
                        BandleHistoryView(entries: model.history)
                    }
                }
            }
            .controlSize(.large)
            .padding(AM.Spacing.screenMargin)
            .frame(maxWidth: AM.Layout.wideRailMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .musicScreenBackground()
        .navigationTitle(String(localized: "Bandle Statistics"))
        .task { await model.loadIfNeeded() }
        .refreshable { await model.reload() }
    }

    private func selectMode(_ mode: BandleMode) {
        AppHaptic.selection.play()
        Task { await model.selectMode(mode) }
    }

    private func selectPeriod(_ period: BandleLeaderboardPeriod) {
        AppHaptic.selection.play()
        Task { await model.selectPeriod(period) }
    }

    private func retry() {
        AppHaptic.selection.play()
        Task { await model.reload() }
    }
}
