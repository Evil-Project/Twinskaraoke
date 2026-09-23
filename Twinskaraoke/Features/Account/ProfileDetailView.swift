import SDWebImageSwiftUI
import SwiftUI

struct ProfileDetailView: View {
    let displayName: String
    let avatarUrl: String?
    let profile: Profile?
    let badges: [Badge]
    let uploadLimits: UploadLimits?
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selected: Badge?
    private let cols = AM.Layout.adaptiveGridColumns(minimum: 96, spacing: 14)
    private var unlocked: [Badge] {
        badges.filter(\.unlocked)
    }

    private var locked: [Badge] {
        badges.filter { !$0.unlocked }
    }

    private var unlockedBadgeCount: Int {
        profile?.unlockedBadges ?? unlocked.count
    }

    private var totalBadgeCount: Int {
        max(profile?.totalBadges ?? badges.count, badges.count)
    }

    private var nextBadge: Badge? {
        locked.first { $0.conditionValue > 0 } ?? locked.first
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 760 : .infinity
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileDetailHeader(
                    displayName: displayName,
                    avatarUrl: avatarUrl,
                    profile: profile,
                    unlockedCount: unlocked.count,
                    totalCount: badges.count
                )
                if !badges.isEmpty {
                    ProfileAchievementStrip(
                        unlockedCount: unlockedBadgeCount,
                        totalCount: totalBadgeCount,
                        nextBadge: nextBadge,
                        onSelect: selectBadge
                    )
                    .transition(bottomTransition)
                }
                if let uploadLimits {
                    StorageSection(limits: uploadLimits)
                }
                if unlocked.isEmpty, locked.isEmpty {
                    MusicEmptyState(
                        title: String(localized: "No Badges Yet"),
                        message: String(localized: "Sing more songs to start unlocking profile badges.")
                    )
                    .padding(.vertical, 28)
                    .transition(emptyStateTransition)
                }
                if !unlocked.isEmpty {
                    BadgeGridSection(
                        title: String(localized: "Unlocked"),
                        items: unlocked,
                        headerCount: profile?.unlockedBadges,
                        cols: cols,
                        onSelect: selectBadge
                    )
                    .transition(bottomTransition)
                }
                if !locked.isEmpty {
                    BadgeGridSection(
                        title: String(localized: "Locked"),
                        items: locked,
                        headerCount: nil,
                        cols: cols,
                        onSelect: selectBadge
                    )
                    .transition(bottomTransition)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: contentMaxWidth, alignment: .top)
            .accessibilityIdentifier(horizontalSizeClass == .regular ? "Profile.WideOverview" : "Profile.CompactOverview")
        }
        .frame(maxWidth: .infinity)
        .scrollIndicators(.hidden)
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { badge in
            BadgeDetailSheet(badge: badge)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func selectBadge(_ badge: Badge) {
        guard !reduceMotion else {
            selected = badge
            return
        }
        withOptionalAnimation(profileAnimation) {
            selected = badge
        }
    }

    private var profileAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }

    private var bottomTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private var emptyStateTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }
}

private struct ProfileDetailHeader: View {
    let displayName: String
    let avatarUrl: String?
    let profile: Profile?
    let unlockedCount: Int
    let totalCount: Int
    var body: some View {
        VStack(spacing: 14) {
            ProfileAvatar(displayName: displayName, avatarUrl: avatarUrl, size: 96)
                .overlay(Circle().strokeBorder(Color(hex: "B47BFF").opacity(0.6), lineWidth: 2))
            VStack(spacing: 6) {
                Text(displayName)
                    .font(.title2.weight(.bold))
                if let level = profile?.level {
                    LevelChipLarge(level: level, title: profile?.levelTitle)
                }
            }
            if let progress = profile?.levelProgress {
                XPBar(
                    progress: progress,
                    totalXP: profile?.totalXP,
                    xpToNextLevel: profile?.xpToNextLevel
                )
            }
            ProfileStatsCard(
                unlocked: profile?.unlockedBadges ?? unlockedCount,
                total: profile?.totalBadges ?? totalCount,
                level: profile?.level ?? 0
            )
        }
    }
}

private struct ProfileAvatar: View {
    let displayName: String
    let avatarUrl: String?
    let size: CGFloat
    var body: some View {
        Group {
            if let urlStr = avatarUrl, let url = URL(string: urlStr), !urlStr.isEmpty {
                WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Color.appPlaceholderSecondary)
            if let first = displayName.first {
                Text(String(first).uppercased())
                    .font(.largeTitle.bold())
                    .foregroundStyle(.secondary)
            } else {
                MusicCircularPlaceholder()
            }
        }
    }
}

private struct LevelChipLarge: View {
    let level: Int
    let title: String?
    var body: some View {
        HStack(spacing: 8) {
            Text("LV \(level)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ProfileTheme.gradient, in: Capsule())
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct XPBar: View {
    let progress: Double
    let totalXP: Int?
    let xpToNextLevel: Int?
    var body: some View {
        VStack(spacing: 6) {
            GradientProgressBar(progress: progress / 100, height: 6)
            HStack {
                if let totalXP {
                    Text("\(totalXP) XP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let xpToNextLevel, xpToNextLevel > 0 {
                    Text("\(xpToNextLevel) to next level")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ProfileStatsCard: View {
    let unlocked: Int
    let total: Int
    let level: Int
    var body: some View {
        HStack(spacing: 0) {
            stat(value: "\(unlocked)", label: String(localized: "Unlocked"))
            Divider().frame(height: 32)
            stat(value: "\(total)", label: String(localized: "Total"))
            Divider().frame(height: 32)
            stat(value: "\(level)", label: String(localized: "Level"))
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProfileAchievementStrip: View {
    let unlockedCount: Int
    let totalCount: Int
    let nextBadge: Badge?
    let onSelect: (Badge) -> Void
    private var completion: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, Double(unlockedCount) / Double(totalCount))
    }

    private var completionText: String {
        "\(unlockedCount) of \(totalCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                AchievementMeter(progress: completion)
                    .frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Achievements")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(completionText) badges unlocked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Keep singing to complete your profile collection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let nextBadge {
                Button {
                    onSelect(nextBadge)
                } label: {
                    NextBadgeCallout(badge: nextBadge)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82, haptic: .selection))
                .contextMenu {
                    Button {
                        onSelect(nextBadge)
                    } label: {
                        Label("View Badge", systemImage: "info.circle")
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        )
    }
}

private struct AchievementMeter: View {
    let progress: Double
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var animatedProgress = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.appControlInactiveFill, lineWidth: 8)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    Color.appAccent,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int((animatedProgress * 100).rounded()))%")
                    .font(.headline)
                    .monospacedDigit()
                Text("done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            setProgress(progress)
        }
        .onChange(of: progress) { _, newValue in
            setProgress(newValue)
        }
        .onChange(of: reduceMotion) { _, _ in
            setProgress(progress)
        }
    }

    private func setProgress(_ newValue: Double) {
        guard !reduceMotion else {
            animatedProgress = newValue
            return
        }
        withOptionalAnimation(AppMotion.gentle) {
            animatedProgress = newValue
        }
    }
}

private struct NextBadgeCallout: View {
    let badge: Badge
    private var progressRatio: Double {
        guard badge.conditionValue > 0 else { return 0 }
        return min(1, Double(badge.currentProgress) / Double(badge.conditionValue))
    }

    private var progressText: String {
        guard badge.conditionValue > 0 else { return String(localized: "View badge details") }
        return "\(badge.currentProgress) / \(badge.conditionValue)"
    }

    var body: some View {
        HStack(spacing: 12) {
            BadgeMiniIcon(badge: badge)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Next Badge")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.appAccent)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Text(progressText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(badge.name)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if badge.conditionValue > 0 {
                    GradientProgressBar(progress: progressRatio, height: 5)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct BadgeMiniIcon: View {
    let badge: Badge
    private var ringColor: Color {
        ProfileTheme.rarityColor(badge.rarity)
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.appBackground)
            if let url = badge.iconURL {
                WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .saturation(badge.unlocked ? 1 : 0)
                        .opacity(badge.unlocked ? 1 : 0.45)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 46, height: 46)
        .overlay(Circle().strokeBorder(ringColor.opacity(0.55), lineWidth: 2))
        .overlay(alignment: .bottomTrailing) {
            if !badge.unlocked {
                Image(systemName: "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(Color.primary.opacity(0.76), in: Circle())
                    .overlay(Circle().strokeBorder(Color.appSecondaryBackground, lineWidth: 2))
            }
        }
    }

    private var placeholder: some View {
        MusicCircularPlaceholder()
    }
}

private struct BadgeGridSection: View {
    let title: String
    let items: [Badge]
    let headerCount: Int?
    let cols: [GridItem]
    let onSelect: (Badge) -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(headerCount ?? items.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(items) { badge in
                    Button {
                        onSelect(badge)
                    } label: {
                        BadgeGridCell(badge: badge)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.82, haptic: .selection))
                    .contextMenu {
                        Button {
                            AppHaptic.selection.play()
                            onSelect(badge)
                        } label: {
                            Label("View Details", systemImage: "info.circle")
                        }
                    }
                    .transition(cellTransition)
                }
            }
        }
    }

    private var cellTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94))
    }
}
