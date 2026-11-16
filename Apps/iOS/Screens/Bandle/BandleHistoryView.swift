import SwiftUI

struct BandleHistoryView: View {
    let entries: [BandleHistoryEntry]

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                String(localized: "No Bandle games yet"),
                systemImage: "clock",
                description: Text(String(localized: "Your completed daily challenges will appear here."))
            )
            .accessibilityIdentifier("Bandle.History.Empty")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    VStack(spacing: 0) {
                        BandleHistoryRow(entry: entry)
                        Divider()
                    }
                }
            }
            .padding(.horizontal, AM.Spacing.l)
            .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
        }
    }
}
