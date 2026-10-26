import SwiftUI

enum ProfileTheme {
    static let gradient = LinearGradient(
        colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
        startPoint: .leading, endPoint: .trailing
    )
    static let radialGradient = LinearGradient(
        colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let rarityColors: [Color] = [
        Color(hex: "8E8E93"),
        Color(hex: "4FA8FF"),
        Color(hex: "B47BFF"),
        Color(hex: "FFB347"),
    ]
    static func rarityColor(_ rarity: Int) -> Color {
        let i = max(0, min(rarity, rarityColors.count - 1))
        return rarityColors[i]
    }
}
