import Foundation

typealias Profile = UserProfile
typealias Badge = AccountBadge

// MARK: - LevelUpModels

struct LevelUpAnnouncement: Identifiable {
    let id = UUID()
    let previousLevel: Int
    let currentLevel: Int
    let levelTitle: String?
}
