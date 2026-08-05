import SwiftUI

/// One song line in a list. Double-click or the hover play button starts it in
/// the context of the list it came from, so the queue matches what's on screen.
struct SongRow: View {
    let song: Song
    let context: [Song]

    @Environment(MacAudioManager.self) private var audio
    // A plain reference, not @State: FavoritesManager is @Observable, so
    // SwiftUI tracks the properties this body reads. @State implied per-view
    // ownership of a process-wide singleton, which reads as a local copy.
    private let favorites = FavoritesManager.shared
    @State private var isHovering = false

    private var isCurrent: Bool { audio.currentSong?.id == song.id }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                SongArtwork(url: song.rowImageURL, size: 36)
                if isHovering || isCurrent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .frame(width: 36, height: 36)
                    Image(systemName: isCurrent && audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }
            .onTapGesture(perform: playOrToggle)

            VStack(alignment: .leading, spacing: 1) {
                Text(song.displayTitle)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.appAccent : .primary)
                    .lineLimit(1)
                Text(song.displayArtist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                favorites.toggle(songID: song.id)
            } label: {
                Image(systemName: favorites.isFavorite(song.id) ? "heart.fill" : "heart")
                    .foregroundStyle(favorites.isFavorite(song.id) ? Color.appAccent : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering || favorites.isFavorite(song.id) ? 1 : 0)
            .help(favorites.isFavorite(song.id) ? "Remove from favourites" : "Add to favourites")

            Text(song.durationText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: playOrToggle)
        .contextMenu {
            Button("Play") { audio.play(song: song, context: context) }
            Button(favorites.isFavorite(song.id) ? "Remove from Favourites" : "Add to Favourites") {
                favorites.toggle(songID: song.id)
            }
        }
    }

    private func playOrToggle() {
        if isCurrent {
            audio.togglePlayPause()
        } else {
            audio.play(song: song, context: context)
        }
    }
}

/// Shared empty/error/loading presentation so every screen behaves the same.
struct StateMessage: View {
    let systemImage: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// Horizontal artwork shelf used by Home.
struct SongShelf: View {
    let title: String
    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(songs) { song in
                        SongCard(song: song, context: songs)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct SongCard: View {
    let song: Song
    let context: [Song]

    @Environment(MacAudioManager.self) private var audio
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                SongArtwork(url: song.imageURL, size: 136, cornerRadius: 8)
                if isHovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.4))
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 136, height: 136)

            Text(song.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(song.displayArtist)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 136, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { audio.play(song: song, context: context) }
    }
}
