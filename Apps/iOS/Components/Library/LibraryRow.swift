import SwiftUI

struct LibraryRow: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The icon's column grows with the icon. At a fixed 30pt, an
    /// accessibility-size glyph spilled out of it and over the title.
    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 30

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AM.Font.rowTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    // Wraps at an accessibility size, where one line cut
                    // "Karaoke Setlists" and "Downloaded" short.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                if let subtitle {
                    Text(subtitle)
                        .font(AM.Font.tileCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
    }
}
