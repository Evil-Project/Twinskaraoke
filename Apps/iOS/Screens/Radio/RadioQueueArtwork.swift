import SwiftUI

struct RadioQueueArtwork: View {
    let song: RadioNowPlaying.SongInfo
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let url = song.artworkURL {
                RemoteArtworkImage(
                    url: ArtworkURLBuilder.variantURL(from: url, variant: .thumbnail) ?? url,
                    cornerRadius: cornerRadius
                )
            } else {
                LinearGradient(
                    colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3.bold())
                        .foregroundStyle(.white.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension RadioNowPlaying.SongInfo {
    var displayTitle: String {
        title ?? text ?? String(localized: "Live Radio")
    }

    var displayArtist: String {
        artist ?? "Twinskaraoke Radio"
    }

    var artworkURL: URL? {
        art.flatMap { URL(string: $0) }
    }
}
