import SwiftUI

/// A load failure reported in line with the Library's content.
///
/// It scrolls with the page. As text in a top safe-area inset it stayed pinned
/// under the navigation bar with nothing behind it, so the shelves scrolled
/// straight through the words.
struct LibraryLoadNotice: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(AM.Spacing.m)
        .frame(maxWidth: AM.Layout.wideContentMaxWidth, alignment: .leading)
        .background(
            Color.appSecondaryBackground,
            in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
        )
        .padding(.horizontal, AM.Spacing.screenMargin)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Library.LoadNotice")
    }
}
