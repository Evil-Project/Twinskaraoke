import Foundation
import SwiftUI

// These shapes now live in TwinskaraokeShared/Models/AccountProfile.swift so
// the Mac and tvOS profile screens decode the same payloads as iOS. The local
// spellings stay as aliases: they are used across the iOS feature code, and the
// field lists were already identical, so there is nothing to migrate.
typealias Profile = UserProfile
typealias Badge = AccountBadge

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

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch h.count {
        case 3: (a, r, g, b) = (255, (v >> 8) * 17, (v >> 4 & 0xF) * 17, (v & 0xF) * 17)
        case 6: (a, r, g, b) = (255, v >> 16, v >> 8 & 0xFF, v & 0xFF)
        case 8: (a, r, g, b) = (v >> 24, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB, red: Double(r) / 255, green: Double(g) / 255,
            blue: Double(b) / 255, opacity: Double(a) / 255
        )
    }
}

struct GradientProgressBar: View {
    let progress: Double
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(progress, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule()
                    .fill(ProfileTheme.gradient)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
    }
}
