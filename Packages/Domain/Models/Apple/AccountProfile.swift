import Foundation

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
