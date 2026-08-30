import SwiftUI

struct iOSAppDevelopmentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let repoURL = URL(string: "https://github.com/Evil-Project/Twinskaraoke")!

    var body: some View {
        developmentContent
            .navigationTitle("iOS App Development")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var developmentContent: some View {
        if horizontalSizeClass == .regular {
            ZStack(alignment: .top) {
                ScreenBackgroundFill(style: .grouped)
                developmentList
                    .frame(maxWidth: 700, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .accessibilityIdentifier("iOSAppDevelopment.WideOverview")
            }
        } else {
            developmentList
        }
    }

    private var developmentList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Twinskaraoke iOS")
                        .font(.headline)
                    Text(
                        "A native SwiftUI client for the Neuro & Evil Karaoke Web Player. Built around the public Neurokaraoke API, with offline downloads, vocal removal, beat-aware crossfade, and Live Radio playback."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("Source Code") {
                Link(destination: repoURL) {
                    HStack(spacing: 14) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("github.com/Evil-Project/Twinskaraoke")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("Open repository")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Section("Tech Stack") {
                techRow("SwiftUI", detail: "Declarative UI throughout")
                techRow("AVFoundation", detail: "Playback, crossfade, vocal-cancel audio mix")
                techRow("Combine", detail: "Player and download state")
                techRow("SDWebImageSwiftUI", detail: "Artwork loading & caching")
            }
            Section("Contributing") {
                Text(
                    "Issues and pull requests are welcome on GitHub. The repository contains build instructions and the project's coding conventions."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }

    private func techRow(_ name: String, detail: String) -> some View {
        HStack {
            Text(name).font(.body)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 1)
    }
}
