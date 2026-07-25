import SDWebImageSwiftUI
import SwiftUI

struct BadgeGridCell: View {
    let badge: Badge
    private var ringColor: Color {
        ProfileTheme.rarityColor(badge.rarity)
    }

    private var progressRatio: Double {
        guard badge.conditionValue > 0 else { return 0 }
        return min(1, Double(badge.currentProgress) / Double(badge.conditionValue))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.appSecondaryBackground)
                if let url = badge.iconURL {
                    WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .saturation(badge.unlocked ? 1 : 0)
                            .opacity(badge.unlocked ? 1 : 0.4)
                    } placeholder: {
                        MusicCircularPlaceholder()
                    }
                } else {
                    MusicCircularPlaceholder()
                }
            }
            .frame(width: 64, height: 64)
            .overlay(
                Circle().strokeBorder(ringColor.opacity(badge.unlocked ? 1 : 0.4), lineWidth: 2)
            )
            .overlay {
                if !badge.unlocked, badge.conditionValue > 0 {
                    Circle()
                        .trim(from: 0, to: progressRatio)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(-2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !badge.unlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color.appBackground)
                        .frame(width: 19, height: 19)
                        .background(Color.primary.opacity(0.72), in: Circle())
                        .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2))
                }
            }
            .shadow(color: ringColor.opacity(badge.unlocked ? 0.22 : 0.08), radius: 8, y: 4)
            Text(badge.name)
                .font(.caption.bold())
                .foregroundStyle(badge.unlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28)
            Group {
                if !badge.unlocked, badge.conditionValue > 0 {
                    Text("\(badge.currentProgress) / \(badge.conditionValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if badge.unlocked {
                    Text("Unlocked")
                        .font(.caption)
                        .foregroundStyle(ringColor)
                }
            }
            .frame(height: 12)
        }
        .contentShape(Rectangle())
    }
}

struct BadgeDetailSheet: View {
    let badge: Badge
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color.appSheetGradientTop, Color.appSheetGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                BadgeDetailIcon(badge: badge)
                BadgeDetailInfo(badge: badge)
                if badge.conditionValue > 0 {
                    BadgeDetailProgress(badge: badge)
                        .padding(.horizontal, 32)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button {
                AppHaptic.light.play()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemBackground), in: Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72))
            .padding(.top, 14)
            .padding(.trailing, 14)
        }
    }
}

private struct BadgeDetailIcon: View {
    let badge: Badge
    var body: some View {
        ZStack {
            Circle().fill(Color.appSecondaryBackground)
            if let url = badge.iconURL {
                WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .saturation(badge.unlocked ? 1 : 0)
                        .opacity(badge.unlocked ? 1 : 0.4)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 128, height: 128)
        .overlay(
            Circle().strokeBorder(ProfileTheme.rarityColor(badge.rarity).opacity(0.85), lineWidth: 3)
        )
        .overlay(alignment: .bottomTrailing) {
            if !badge.unlocked {
                Image(systemName: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(Color.appBackground)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.76), in: Circle())
                    .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 3))
            }
        }
        .shadow(color: ProfileTheme.rarityColor(badge.rarity).opacity(0.22), radius: 16, y: 8)
    }

    private var placeholder: some View {
        MusicCircularPlaceholder()
    }
}

private struct BadgeDetailInfo: View {
    let badge: Badge
    var body: some View {
        VStack(spacing: 8) {
            Text(badge.name)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                BadgeStatusPill(unlocked: badge.unlocked)
                BadgeRarityPill(rarity: badge.rarity)
            }
            if let description = badge.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }
}

private struct BadgeStatusPill: View {
    let unlocked: Bool
    var body: some View {
        Label(
            unlocked ? "Unlocked" : "Locked",
            systemImage: unlocked ? "checkmark.circle.fill" : "lock.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(unlocked ? Color.green : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.appControlInactiveFill, in: Capsule())
    }
}

private struct BadgeRarityPill: View {
    let rarity: Int
    private var label: String {
        switch rarity {
        case 0: "Common"
        case 1: "Rare"
        case 2: "Epic"
        default: "Legendary"
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ProfileTheme.rarityColor(rarity))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(ProfileTheme.rarityColor(rarity).opacity(0.12), in: Capsule())
    }
}

private struct BadgeDetailProgress: View {
    let badge: Badge
    private var ratio: Double {
        guard badge.conditionValue > 0 else { return 0 }
        return min(1, Double(badge.currentProgress) / Double(badge.conditionValue))
    }

    var body: some View {
        VStack(spacing: 8) {
            GradientProgressBar(progress: ratio, height: 7)
            Text("\(badge.currentProgress) / \(badge.conditionValue)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
