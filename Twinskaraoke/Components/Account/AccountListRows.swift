import SDWebImageSwiftUI
import SwiftUI

struct ProfileHeaderRow: View {
    let displayName: String
    let avatarUrl: String?
    let level: Int?
    let levelTitle: String?
    let levelProgress: Double?
    let xpToNextLevel: Int?
    var body: some View {
        HStack(spacing: 16) {
            avatarView
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                if let level {
                    levelChip(level: level, title: levelTitle)
                }
                if let progress = levelProgress {
                    xpProgress(progress: progress, xpRemaining: xpToNextLevel)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayName)
        .accessibilityValue(profileAccessibilityValue)
    }

    private var profileAccessibilityValue: String {
        var parts: [String] = []
        if let level {
            parts.append("Level \(level)")
        }
        if let levelTitle, !levelTitle.isEmpty {
            parts.append(levelTitle)
        }
        if let xpToNextLevel, xpToNextLevel > 0 {
            parts.append("\(xpToNextLevel) XP to next level")
        }
        return parts.joined(separator: ", ")
    }

    private func levelChip(level: Int, title: String?) -> some View {
        HStack(spacing: 6) {
            Text("LV \(level)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ProfileTheme.gradient, in: Capsule())
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func xpProgress(progress: Double, xpRemaining: Int?) -> some View {
        GradientProgressBar(progress: progress / 100, height: 4)
        if let xpRemaining, xpRemaining > 0 {
            Text("\(xpRemaining) XP to next level")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlStr = avatarUrl, let url = URL(string: urlStr), !urlStr.isEmpty {
            WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initials
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            ProfileTheme.radialGradient
            Text(String(displayName.prefix(1).uppercased()))
                .font(.title2.bold())
                .foregroundStyle(.white)
        }
    }
}

struct UnlockedBadgesRow: View {
    let badges: [Badge]
    let unlockedCount: Int
    let totalCount: Int
    @State private var selected: Badge?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Badges")
                    .font(.headline)
                Spacer()
                Text("\(unlockedCount) / \(totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(badges) { badge in
                        Button {
                            AppHaptic.selection.play()
                            selected = badge
                        } label: {
                            BadgeIcon(badge: badge)
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78))
                        .accessibilityLabel(badge.name)
                        .accessibilityValue(accessibilityValue(for: badge))
                        .accessibilityHint("Shows badge details.")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 8)
        .sheet(item: $selected) { badge in
            BadgeDetailSheet(badge: badge)
                .presentationDetents([.medium])
        }
    }

    private func accessibilityValue(for badge: Badge) -> String {
        var parts = [badge.unlocked ? "Unlocked" : "Locked", "Rarity \(badge.rarity)"]
        if !badge.unlocked, badge.conditionValue > 0 {
            parts.append("\(badge.currentProgress) of \(badge.conditionValue)")
        }
        if let description = badge.description, !description.isEmpty {
            parts.append(description)
        }
        return parts.joined(separator: ", ")
    }
}

struct BadgeIcon: View {
    let badge: Badge
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Color(.secondarySystemBackground))
                if let url = badge.iconURL {
                    WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
                        image.resizable().scaledToFit().padding(4)
                    } placeholder: {
                        MusicCircularPlaceholder()
                    }
                } else {
                    MusicCircularPlaceholder()
                }
            }
            .frame(width: 44, height: 44)
            .overlay(
                Circle().strokeBorder(ProfileTheme.rarityColor(badge.rarity), lineWidth: 1.5)
            )
            Text(badge.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 56)
        }
    }
}
