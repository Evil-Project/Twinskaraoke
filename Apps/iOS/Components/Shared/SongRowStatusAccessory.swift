import SwiftUI

/// The one trailing accessory of a song row, then the menu. Apple Music's rows
/// show a single status glyph; this used to stack a download badge, a duration
/// and an ellipsis side by side, which read busier than the artwork it sat next
/// to. Download state outranks the duration because it is the transient,
/// actionable one — the duration is still on the row's accessibility value
/// either way.
struct SongRowStatusAccessory: View {
    let status: SongDownloadStatus
    let durationText: String
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At an accessibility text size the duration gives its width to the
    /// title. Beside a 53pt "3:27" the title had room for four letters.
    static func showsDuration(_ durationText: String, isAccessibilitySize: Bool) -> Bool {
        !durationText.isEmpty && !isAccessibilitySize
    }

    var body: some View {
        Group {
            if status.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(statusLabel(String(localized: "Downloaded")))
                    .transition(statusTransition)
            } else if status.isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(statusLabel(String(localized: "Downloading")))
                    .transition(statusTransition)
            } else if Self.showsDuration(durationText, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                Text(durationText)
                    .font(AM.Font.timecode)
                    .foregroundStyle(.secondary)
                    .transition(statusTransition)
            }
        }
        .animation(reduceMotion ? nil : AppMotion.quick, value: status)
    }

    /// The status glyph replaces the duration rather than sitting beside it, so
    /// it has to carry the duration itself. `songRowAccessibility` also puts the
    /// duration on the row, but six of the screens that draw a SongRow never
    /// apply that modifier — without this the time is simply gone for VoiceOver
    /// on any downloaded row there.
    private func statusLabel(_ status: String) -> String {
        durationText.isEmpty ? status : "\(status), \(durationText)"
    }

    private var statusTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)
    }
}
