import SDWebImageSwiftUI
import SwiftUI

struct AboutView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    @State private var versionTapCount = 0
    @State private var showEasterEgg = false
    var body: some View {
        aboutContent
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showEasterEgg) {
                EasterEggView()
            }
    }

    @ViewBuilder
    private var aboutContent: some View {
        if horizontalSizeClass == .regular {
            ZStack(alignment: .top) {
                ScreenBackgroundFill(style: .grouped)
                aboutList
                    .frame(maxWidth: 700, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .accessibilityIdentifier("About.WideOverview")
            }
        } else {
            aboutList
        }
    }

    private var aboutList: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    appIconView
                    Text("Twinskaraoke")
                        .font(.title2.bold())
                    Button(action: handleVersionTap) {
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Version \(appVersion)")
                    Text("NEUROKARAOKE.COM • EVILKARAOKE.COM • TWINSKARAOKE.COM")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }
            Section("About Neuro & Evil Karaoke Web Player") {
                Text(AboutContent.intro)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                Text(AboutContent.unofficialNotice)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            Section("Explore") {
                NavigationLink {
                    FeaturesContentView()
                } label: {
                    AboutLinkRow(
                        icon: "sparkles",
                        color: .appAccent,
                        title: "Features & Content",
                        subtitle: "Catalog, radio, galleries, games, and community tools"
                    )
                }
                NavigationLink {
                    CreditsView()
                } label: {
                    AboutLinkRow(
                        icon: "heart.fill",
                        color: .pink,
                        title: "Credits",
                        subtitle: "Artists, maintainers, testers, and contributors"
                    )
                }
                NavigationLink {
                    LanguageSupportView()
                } label: {
                    AboutLinkRow(
                        icon: "globe",
                        color: .blue,
                        title: "Language Support",
                        subtitle: "Available app languages and regional behavior"
                    )
                }
                NavigationLink {
                    iOSAppDevelopmentView()
                } label: {
                    AboutLinkRow(
                        icon: "hammer.fill",
                        color: .orange,
                        title: "iOS App Development",
                        subtitle: "Source code, stack, and contribution notes"
                    )
                }
                NavigationLink {
                    ContactSupportView()
                } label: {
                    AboutLinkRow(
                        icon: "envelope.fill",
                        color: .indigo,
                        title: "Contact",
                        subtitle: "Credit corrections and take-down requests"
                    )
                }
            }
            Section("Resources") {
                Link(destination: URL(string: "https://radio.twinskaraoke.com")!) {
                    AboutLinkRow(
                        icon: "dot.radiowaves.left.and.right", color: .appAccent,
                        title: "Neuro 21 Radio Station"
                    )
                }
                Link(destination: URL(string: "\(StorageHost.api)")!) {
                    AboutLinkRow(icon: "server.rack", color: .blue, title: "API Service")
                }
                Link(destination: URL(string: "https://www.youtube.com/@neurokaraoke")!) {
                    AboutLinkRow(
                        icon: "play.rectangle.fill", color: .appAccent, title: "Video Gallery (YouTube)"
                    )
                }
                Link(destination: URL(string: "https://github.com/Evil-Project/Twinskaraoke")!) {
                    AboutLinkRow(
                        icon: "chevron.left.forwardslash.chevron.right", color: .black,
                        title: "iOS App Source (GitHub)"
                    )
                }
            }
            Section("Legal") {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    AboutLinkRow(
                        icon: "hand.raised.fill",
                        color: .gray,
                        title: "Privacy Policy",
                        subtitle: "Data storage, network services, and user choices"
                    )
                }
                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    AboutLinkRow(
                        icon: "doc.text.fill",
                        color: .gray,
                        title: "Terms of Service",
                        subtitle: "Community-use rules and legal disclaimers"
                    )
                }
                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    AboutLinkRow(
                        icon: "shippingbox.fill",
                        color: .orange,
                        title: "Open Source Licenses",
                        subtitle: "Third-party package acknowledgements"
                    )
                }
            }
            Section {
                Text("© 2026 Neuro & Evil Karaoke Web Player\nFan-made by Soul. Unofficial.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }

    @ViewBuilder
    private var appIconView: some View {
        if !AppLogoData.shared.isEmpty {
            AnimatedImage(data: AppLogoData.shared)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
                .transaction { $0.animation = nil }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ProfileTheme.radialGradient)
                Image(systemName: "music.mic")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 96, height: 96)
            .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
        }
    }

    private func handleVersionTap() {
        versionTapCount += 1
        if versionTapCount == 10 {
            showEasterEgg = true
        } else if versionTapCount >= 20 {
            versionTapCount = 0
            let newState = !DeveloperMode.isEnabled
            DeveloperMode.isEnabled = newState
        }
    }
}

private struct FeaturesContentView: View {
    var body: some View {
        AboutDetailList(accessibilityIdentifier: "About.FeaturesContent") {
            Section {
                AboutHeroRow(
                    icon: "sparkles",
                    color: .appAccent,
                    title: "Features & Content",
                    subtitle:
                    "A structured map of the web player, radio, galleries, community systems, and native app features."
                )
            }
            Section("Music") {
                featureRows(AboutContent.musicFeatures, color: .appAccent)
            }
            Section("Community") {
                featureRows(AboutContent.communityFeatures, color: .pink)
            }
            Section("Play") {
                featureRows(AboutContent.playFeatures, color: .blue)
            }
            Section("Apps") {
                featureRows(AboutContent.appFeatures, color: .green)
            }
        }
        .navigationTitle("Features & Content")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRows(_ features: [AboutContent.FeatureGroup], color: Color) -> some View {
        ForEach(features) { feature in
            AboutFeatureRow(feature: feature, color: color)
        }
    }
}

private struct AboutFeatureRow: View {
    let feature: AboutContent.FeatureGroup
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AboutIconBadge(systemImage: feature.systemImage, color: color, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.title)
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                    Text(feature.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            AboutBulletList(items: feature.bullets)
                .padding(.leading, 44)
        }
        .padding(.vertical, 5)
    }
}

private struct LanguageSupportView: View {
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageMode) ?? .system
    }

    var body: some View {
        AboutDetailList(accessibilityIdentifier: "About.LanguageSupport") {
            Section {
                AboutHeroRow(
                    icon: "globe",
                    color: .blue,
                    title: "Language Support",
                    subtitle:
                    "The app follows your selected language setting and keeps regional storage behavior separate from interface language."
                )
            }
            Section("App Languages") {
                ForEach(AppLanguage.allCases) { language in
                    LanguageSupportRow(
                        language: language,
                        isSelected: language == selectedLanguage
                    )
                }
            }
            Section("Coverage") {
                AboutInfoRow(
                    icon: "iphone",
                    color: .appAccent,
                    title: "Native App",
                    detail:
                    "Interface strings use the app language selected in Music settings. System mode follows the current device locale."
                )
                AboutInfoRow(
                    icon: "safari.fill",
                    color: .blue,
                    title: "Web Player",
                    detail:
                    "The web player provides localized navigation and content where translations are available."
                )
                AboutInfoRow(
                    icon: "server.rack",
                    color: .green,
                    title: "Storage Region",
                    detail:
                    "Media hosts are selected separately from language, using the device region unless an nk.storageRegion override is set."
                )
            }
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    AboutLinkRow(
                        icon: "gearshape.fill",
                        color: .gray,
                        title: "Open Music Settings",
                        subtitle: "Change language, appearance, playback, and storage preferences"
                    )
                }
            }
        }
        .navigationTitle("Language Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LanguageSupportRow: View {
    let language: AppLanguage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AboutIconBadge(systemImage: icon, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(language.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appAccent)
                    .accessibilityLabel("Selected")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch language {
        case .system:
            "Use the current device locale."
        default:
            "Locale \(language.localeIdentifier)"
        }
    }

    private var icon: String {
        switch language {
        case .system:
            "iphone"
        case .english:
            "textformat"
        case .simplifiedChinese, .traditionalChinese:
            "character.book.closed.fill"
        case .japanese:
            "character.textbox"
        case .french, .german, .finnish, .ukrainian:
            "text.bubble.fill"
        }
    }

    private var color: Color {
        switch language {
        case .system:
            .gray
        case .english:
            .appAccent
        case .simplifiedChinese, .traditionalChinese:
            .red
        case .japanese:
            .purple
        case .french:
            .blue
        case .german:
            .orange
        case .finnish:
            .teal
        case .ukrainian:
            .yellow
        }
    }
}

private struct ContactSupportView: View {
    var body: some View {
        AboutDetailList(accessibilityIdentifier: "About.ContactSupport") {
            Section {
                AboutHeroRow(
                    icon: "envelope.fill",
                    color: .indigo,
                    title: "Contact",
                    subtitle:
                    "Use the project contact for credit corrections, copyright concerns, and take-down requests."
                )
            }
            Section("Primary Contact") {
                AboutInfoRow(
                    icon: "person.crop.circle.badge.questionmark",
                    color: .indigo,
                    title: "Discord",
                    detail: "@soul1419"
                )
            }
            Section("Good Reasons To Reach Out") {
                AboutBulletList(
                    items: [
                        "Credit corrections for artwork, clips, soundbites, metadata, or badges.",
                        "Copyright take-down requests.",
                        "Artist permission updates.",
                        "Broken links or incorrect public attribution.",
                    ]
                )
                .padding(.vertical, 4)
            }
            Section("Take-Down Requests") {
                AboutInfoRow(
                    icon: "doc.text.magnifyingglass",
                    color: .orange,
                    title: "Include The Exact Item",
                    detail:
                    "Send the song, artwork, video, quote, or playlist URL plus the reason for the request."
                )
                AboutInfoRow(
                    icon: "person.text.rectangle",
                    color: .blue,
                    title: "Include Ownership Context",
                    detail:
                    "Share the creator name, original post, or permission record so the team can verify the request quickly."
                )
            }
            Section("Project Status") {
                AboutInfoRow(
                    icon: "info.circle.fill",
                    color: .gray,
                    title: "Unofficial Fan Project",
                    detail: AboutContent.unofficialNotice
                )
            }
        }
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        AboutLegalContentView(
            title: "Privacy Policy",
            icon: "hand.raised.fill",
            color: .gray,
            summary: AboutContent.privacySummary,
            sections: AboutContent.privacySections
        )
    }
}

private struct TermsOfServiceView: View {
    var body: some View {
        AboutLegalContentView(
            title: "Terms of Service",
            icon: "doc.text.fill",
            color: .gray,
            summary: AboutContent.termsSummary,
            sections: AboutContent.termsSections
        )
    }
}

private struct AboutLegalContentView: View {
    let title: String
    let icon: String
    let color: Color
    let summary: String
    let sections: [AboutContent.LegalSection]

    var body: some View {
        AboutDetailList(
            accessibilityIdentifier: "About.\(title.replacingOccurrences(of: " ", with: ""))"
        ) {
            Section {
                AboutHeroRow(
                    icon: icon,
                    color: color,
                    title: title,
                    subtitle: summary
                )
            }
            ForEach(sections) { legalSection in
                Section(legalSection.title) {
                    if let body = legalSection.body {
                        LinkifiedText(text: body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 2)
                    }
                    AboutBulletList(items: legalSection.bullets)
                        .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EasterEggView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.appSheetGradientTop, .appSheetGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 20) {
                AnimatedImage(url: URL(string: "\(StorageHost.base)/media/nuero_.gif"))
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 24)
                    .transaction { $0.animation = nil }
                Text("404 Not Found")
                    .font(.title.monospaced().bold())
                    .foregroundStyle(.primary)
                Text("You've reached the empty place")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.7, haptic: .selection))
            .padding()
        }
    }
}
