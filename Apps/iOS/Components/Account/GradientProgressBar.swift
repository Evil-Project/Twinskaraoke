import SwiftUI

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
