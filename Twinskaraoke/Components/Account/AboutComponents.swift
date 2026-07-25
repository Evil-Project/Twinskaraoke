import SwiftUI

struct AboutLinkRow: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            AboutIconBadge(systemImage: icon, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, subtitle == nil ? 1 : 3)
        .accessibilityElement(children: .combine)
    }
}

struct AboutDetailList<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let accessibilityIdentifier: String
    private let content: () -> Content

    init(accessibilityIdentifier: String, @ViewBuilder content: @escaping () -> Content) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            ZStack(alignment: .top) {
                Color.appGroupedBackground.ignoresSafeArea()
                detailList
                    .frame(maxWidth: 700, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
        } else {
            detailList
        }
    }

    private var detailList: some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
    }
}

struct AboutIconBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.63, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size + 6, height: size)
    }
}

struct AboutHeroRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AboutIconBadge(systemImage: icon, color: color, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

struct AboutInfoRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AboutIconBadge(systemImage: icon, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct AboutBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 4, height: 4)
                    LinkifiedText(text: item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct LinkifiedText: View {
    let text: String
    var body: some View {
        Text(LinkifiedText.attributedString(from: text))
    }

    private static func attributedString(from text: String) -> AttributedString {
        var result = AttributedString()
        for part in split(text) {
            switch part {
            case let .text(s):
                result.append(AttributedString(s))
            case let .url(s, url):
                result.append(
                    AttributedString(
                        s,
                        attributes: AttributeContainer([
                            .link: url,
                            .foregroundColor: UIColor.systemBlue,
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                        ])
                    )
                )
            }
        }
        return result
    }

    private enum Part {
        case text(String)
        case url(String, URL)
    }

    private static let detector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func split(_ string: String) -> [Part] {
        guard let detector else { return [.text(string)] }
        let nsRange = NSRange(string.startIndex ..< string.endIndex, in: string)
        let matches = detector.matches(in: string, options: [], range: nsRange)
        if matches.isEmpty { return [.text(string)] }
        var parts: [Part] = []
        var cursor = string.startIndex
        for match in matches {
            guard let range = Range(match.range, in: string), let url = match.url else { continue }
            if cursor < range.lowerBound {
                parts.append(.text(String(string[cursor ..< range.lowerBound])))
            }
            parts.append(.url(String(string[range]), url))
            cursor = range.upperBound
        }
        if cursor < string.endIndex {
            parts.append(.text(String(string[cursor ..< string.endIndex])))
        }
        return parts
    }
}
