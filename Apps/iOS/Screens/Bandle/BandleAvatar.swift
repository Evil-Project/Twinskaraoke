import SDWebImageSwiftUI
import SwiftUI

struct BandleAvatar: View {
    let url: URL?

    var body: some View {
        WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
    }
}
