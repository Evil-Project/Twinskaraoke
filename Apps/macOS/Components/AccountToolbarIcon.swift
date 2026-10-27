import SwiftUI

/// Toolbar account button contents: the user's avatar once signed in, falling
/// back to the system person glyph. Kept small and circular so it reads as an
/// avatar rather than another toolbar action.
struct AccountToolbarIcon: View {
    let auth: MacAuthManager

    private let size: CGFloat = 20

    var body: some View {
        Group {
            if auth.isLoggedIn, let url = auth.avatarURL {
                MacRemoteImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    fallback
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        Image(systemName: auth.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(auth.isLoggedIn ? Color.appAccent : .secondary)
    }
}
