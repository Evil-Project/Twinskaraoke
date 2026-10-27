import Foundation

struct LevelUpAnnouncement: Identifiable {
    let id = UUID()
    let previousLevel: Int
    let currentLevel: Int
    let levelTitle: String?
}
