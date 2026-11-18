import SwiftUI

/// The "LIVE RADIO · N listening" line over the radio player's title.
///
/// At an accessibility text size the listener count moves to its own line and
/// both lines may wrap, rather than sharing one line and truncating to
/// "LIV… · 24…".
struct RadioLiveMeta: View {
    let listeners: Int?
    let isPlaying: Bool
    /// Pauses the live dot while the player is parked below the screen.
    var isPaused = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if RadioPlayerLayoutStyle.stacksLiveMeta(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
            VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                liveLabel
                if let listeners {
                    listenersText(listeners)
                }
            }
            // The player's column squeezes the title block vertically, which
            // truncates a line before it can wrap.
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 6) {
                liveLabel
                if let listeners {
                    Text("·")
                        .font(AM.Font.eyebrow)
                        .foregroundStyle(.tertiary)
                    listenersText(listeners)
                }
            }
        }
    }

    private var liveLabel: some View {
        HStack(spacing: 6) {
            RadioLiveDot(isPlaying: isPlaying, isPaused: isPaused)
            Text("LIVE RADIO")
                .font(AM.Font.eyebrow)
                .textCase(.uppercase)
                .tracking(1.2)
                // The live indicator, so it keeps the accent the dot wears
                // rather than an eyebrow's usual secondary colour.
                .foregroundStyle(Color.appAccent)
        }
    }

    private func listenersText(_ count: Int) -> some View {
        Text("\(count) listening")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
