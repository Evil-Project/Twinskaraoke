import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private struct Credit: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let url: URL?
    }

    private let credits: [Credit] = [
        Credit(
            name: "SDWebImageSwiftUI",
            detail: "MIT License",
            url: URL(string: "https://github.com/SDWebImage/SDWebImageSwiftUI")
        ),
        Credit(
            name: "SDWebImage",
            detail: "MIT License",
            url: URL(string: "https://github.com/SDWebImage/SDWebImage")
        ),
        Credit(
            name: "SF Symbols",
            detail: "© Apple Inc.",
            url: URL(string: "https://developer.apple.com/sf-symbols/")
        ),
    ]
    var body: some View {
        acknowledgementsContent
            .navigationTitle("Open Source Licenses")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var acknowledgementsContent: some View {
        if horizontalSizeClass == .regular {
            ZStack(alignment: .top) {
                ScreenBackgroundFill(style: .grouped)
                acknowledgementsList
                    .frame(maxWidth: 640, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .accessibilityIdentifier("Acknowledgements.WideOverview")
            }
        } else {
            acknowledgementsList
        }
    }

    private var acknowledgementsList: some View {
        List(credits) { credit in
            VStack(alignment: .leading, spacing: 4) {
                Text(credit.name)
                    .font(.body.bold())
                Text(credit.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let url = credit.url {
                    Link(url.absoluteString, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }
}
