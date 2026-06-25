import SwiftUI

struct LevelUpSheet: View {
    let announcement: LevelUpAnnouncement
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(ProfileTheme.gradient.opacity(0.22))
                    Image(systemName: "sparkles")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 112, height: 112)

                VStack(spacing: 8) {
                    Text("Level Up")
                        .font(.title3.weight(.bold))
                    Text("You reached Level \(announcement.currentLevel)")
                        .font(.title2.weight(.heavy))
                        .multilineTextAlignment(.center)
                    if let title = announcement.levelTitle, !title.isEmpty {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if announcement.previousLevel > 0 {
                        Text("Congratulations on moving up from Level \(announcement.previousLevel).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Button("Keep Going") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GlassXButton(action: { dismiss() })
                .padding(.top, 14)
                .padding(.trailing, 16)
        }
    }
}
