import SwiftUI

struct CreditsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        creditsContent
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var creditsContent: some View {
        if horizontalSizeClass == .regular {
            ZStack(alignment: .top) {
                ScreenBackgroundFill(style: .grouped)
                creditsList
                    .frame(maxWidth: 700, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .accessibilityIdentifier("Credits.WideOverview")
            }
        } else {
            creditsList
        }
    }

    private var creditsList: some View {
        List {
            Section("Site Creation & Management") {
                creditRow(name: "Soul", detail: "Creator & Developer")
            }
            
            Section("iOS App Developers") {
                creditRow(name: "XiaoYuan151", detail: "Main Developer", url: "https://github.com/XiaoYuan151")
                creditRow(name: "SillyProotSoda", detail: "Main Developer", url: "https://sillyprootsoda.com")
                creditRow(name: "MagicBytes", detail: "Maintainer", url: "https://github.com/Mag1cByt3s")
            }
            
            Section("Banner & Branding") {
                creditRow(name: "Fians", detail: "Website banner art", url: "https://x.com/fiansand")
                creditRow(name: "Promote", detail: "Banner editing")
                creditRow(name: "Shinbaru", detail: "Website logo", url: "https://x.com/_shinbaru")
            }
            Section("Coin Art") {
                creditRow(
                    name: "WindSketchy",
                    detail: "Neuro Coin, Evil Coin, and Twins Coin artwork",
                    url: "https://x.com/WindSketchy"
                )
            }
            Section("Additional Contributions") {
                creditRow(
                    name: "Promote", detail: "Twitch poll vote retrieval; manages Neuro & Evil Quotes"
                )
                creditRow(name: "FlashFire8", detail: "Video gallery editing and uploads")
                creditRow(name: "Rachinova & CJ", detail: "Soundbite creation and editing")
                creditRow(name: "Aferil", detail: "Creator and maintainer of the Karaoke App")
                creditRow(name: "Emuz", detail: "Badge art editing", url: "https://x.com/possiblyemuz")
            }
            Section("Internal Testing & Metadata") {
                Text(
                    "Big thanks for assisting with internal testing, bug reporting, and maintaining "
                        + "accurate song metadata across the site:\n\n"
                        + "flashfire8 • promote. • emuz • germaninfantry • magnettileman • waya13 • "
                        + "kyarashard • ttsuyuki • nyss_7 • isrlygood • rachinova • ninjakai03 • "
                        + "czadymny • gbritannia • sir_recker • dodo8071795"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
            Section("Special Thanks") {
                creditRow(
                    name: "Waya", detail: "Helped obtain artist permissions from B2",
                    url: "https://x.com/waya13"
                )
                creditRow(
                    name: "Dodo", detail: "Helped upload a large number of artworks",
                    url: "https://x.com/dodo8071795"
                )
            }
            Section("Historical Archive Source") {
                Text(
                    "All cover files dated November 26, 2025 and earlier are retrieved from the "
                        + "Unofficial Neuro Karaoke Archive (V3).\n\n"
                        + "Currently managed by: @ninjakai03 (mm2wood), @turuumgl, @nyss_7, @inforno_fire"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
            Section("Community Artwork") {
                Text(
                    "All artwork displayed on this site is used with explicit permission from the "
                        + "respective artists. The following artists have granted permission for their "
                        + "artwork to be used on this website:"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                ForEach(CreditsArtists.all, id: \.0) { artist in
                    ArtistCreditRow(name: artist.0, link: artist.1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }

    private func creditRow(name: String, detail: String, url: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.body.bold())
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            if let url, let u = URL(string: url) {
                Link(url, destination: u).font(.caption).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
