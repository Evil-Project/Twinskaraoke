import SDWebImageSwiftUI
import SwiftUI

struct AccountToolbarButton: View {
    @AppStorage("nk.username") private var username: String = ""
    @AppStorage("nk.avatar") private var avatarUrl: String = ""

    var body: some View {
        NavigationLink {
            DeferredView { AccountView() }
        } label: {
            if let url = avatarURL {
                ToolbarAvatarLabel(url: url)
            } else {
                ToolbarIconLabel(systemImage: "person.fill")
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
        .accessibilityIdentifier("AccountToolbarButton")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens account and settings.")
    }

    private var avatarURL: URL? {
        let trimmed = avatarUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var displayName: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var accessibilityLabel: String {
        displayName.isEmpty ? String(localized: "Account") : String(localized: "Account, \(displayName)")
    }
}

private struct ToolbarAvatarLabel: View {
    let url: URL

    var body: some View {
        avatarImage(diameter: 30)
    }

    private func avatarImage(diameter: CGFloat) -> some View {
        WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: "person.fill")
                .font(.headline)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }
}
