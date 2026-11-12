import SwiftUI

/// Says that Home or New is showing the copy saved on this device because the
/// last load got nothing back. Sits above the first shelf and scrolls with
/// it, in the Library notice's look.
struct HomeSavedContentNotice: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                Text("Couldn't Refresh")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("Showing what was saved on this device. Pull down to try again.")
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "wifi.slash")
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
        .accessibilityIdentifier("home.savedContentNotice")
    }
}
