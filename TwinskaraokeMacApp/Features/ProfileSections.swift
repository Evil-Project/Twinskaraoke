import SwiftUI

/// Avatar, display name, level and XP progress. Mirrors the tvOS
/// `profileHeader`, laid out horizontally for a Mac window.
struct ProfileHeader: View {
    let auth: MacAuthManager

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                Text(auth.profile?.displayName ?? auth.username ?? "Signed in")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 10) {
                    if let level = auth.profile?.level {
                        Text("Level \(level)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appAccent)
                    }
                    if let title = auth.profile?.levelTitle, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let totalXP = auth.profile?.totalXP {
                    Text("\(totalXP.formatted()) XP")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let progress = auth.profile?.levelProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: min(max(progress, 0), 1))
                            .progressViewStyle(.linear)
                            .tint(.appAccent)
                            .frame(maxWidth: 320)
                        if let xp = auth.profile?.xpToNextLevel {
                            Text("\(xp.formatted()) XP to next level")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if auth.profile == nil, auth.isRefreshingProfile {
                    ProgressView().controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var avatar: some View {
        Group {
            if let url = auth.avatarURL {
                MacRemoteImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderAvatar
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
    }
}

struct UploadLimitsSection: View {
    let limits: UploadLimits

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upload Limits")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                metric("Songs", "\(limits.currentSongCount) / \(limits.maxSongs)")
                metric("Storage", "\(Self.bytes(limits.usedStorageBytes)) / \(Self.bytes(limits.maxStorageBytes))")
                metric("Playlists", "\(limits.currentPlaylistCount) / \(limits.playlistLimit)")
                metric("Songs per playlist", "\(limits.songPerPlaylistLimit)")
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private static func bytes(_ count: Int64) -> String {
        // allowsNonnumericFormatting defaults to true, which renders 0 as
        // "Zero KB" — reads as a bug next to "1 GB".
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: count)
    }
}

struct BadgesSection: View {
    let badges: [AccountBadge]

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Badges").font(.headline)
                Text("\(badges.filter(\.unlocked).count) of \(badges.count) unlocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(badges) { badge in
                    BadgeCard(badge: badge)
                }
            }
        }
    }
}

struct BadgeCard: View {
    let badge: AccountBadge

    var body: some View {
        VStack(spacing: 6) {
            MacRemoteImage(url: badge.iconURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "rosette")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)
            // Locked badges are dimmed and desaturated rather than hidden, so
            // there's something to aim for.
            .saturation(badge.unlocked ? 1 : 0)
            .opacity(badge.unlocked ? 1 : 0.35)

            Text(badge.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(badge.unlocked ? .primary : .secondary)

            if !badge.unlocked, badge.conditionValue > 0 {
                Text("\(badge.currentProgress)/\(badge.conditionValue)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(badge.description ?? badge.name)
    }
}
