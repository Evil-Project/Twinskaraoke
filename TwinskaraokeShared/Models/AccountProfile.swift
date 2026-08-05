import Foundation

/// Account profile, badge and upload-limit shapes returned by
/// `/api/badge/profile` and `/api/user/upload-limits`.
///
/// These began life inside the tvOS `TVAuthManager`; they moved here when the
/// Mac app needed the same profile screen. Nothing in them is platform
/// specific — plain `Decodable` value types over Foundation — so every target
/// that already compiles `TwinskaraokeShared` gets them for free.

struct ProfileResponse: Decodable, Sendable {
    let profile: UserProfile
    let badges: [AccountBadge]?
}

struct UserProfile: Decodable, Sendable {
    let displayName: String
    let avatarUrl: String?
    let level: Int?
    let levelTitle: String?
    let totalXP: Int?
    let totalBadges: Int?
    let unlockedBadges: Int?
    let levelProgress: Double?
    let xpToNextLevel: Int?

    var avatarURL: URL? {
        Self.remoteURL(from: avatarUrl)
    }

    private static func remoteURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: "\(StorageHost.base)\(ArtworkURLBuilder.normalizedPath(value))")
    }
}

struct AccountBadge: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let rarity: Int
    let unlocked: Bool
    let currentProgress: Int
    let conditionValue: Int
    let media: BadgeMedia?

    var iconURL: URL? {
        ArtworkURLBuilder.imageURL(
            cloudflareID: media?.cloudflareId,
            path: nil,
            variant: .thumbnail
        )
    }
}

struct BadgeMedia: Decodable, Sendable {
    let cloudflareId: String?
}

struct UploadLimits: Decodable, Sendable {
    let maxSongs: Int
    let maxStorageBytes: Int64
    let usedStorageBytes: Int64
    let currentSongCount: Int
    let currentPlaylistCount: Int
    let playlistLimit: Int
    let songPerPlaylistLimit: Int
}
