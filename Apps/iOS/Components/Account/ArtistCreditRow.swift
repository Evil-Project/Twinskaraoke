import SwiftUI

struct ArtistCreditRow: View {
    let name: String
    let link: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.body)
            if let url = URL(string: link), !link.isEmpty {
                Link(link, destination: url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No socials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
}
