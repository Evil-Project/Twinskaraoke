import SwiftUI

struct GallerySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .scaledSystemFont(size: 22, weight: .bold)
            .padding(.horizontal, 16)
    }
}
