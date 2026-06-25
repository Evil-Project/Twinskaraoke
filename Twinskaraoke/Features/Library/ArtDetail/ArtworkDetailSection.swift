import SwiftUI

struct ArtworkDetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .scaledSystemFont(size: 13, weight: .semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .scaledSystemFont(size: 15, weight: .regular)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        }
    }
}
