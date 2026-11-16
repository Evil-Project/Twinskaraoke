import SwiftUI

/// The answer once the game is over: the full song with playback, the usual
/// song actions, and a way into the app's player.
struct BandleRevealedSongCard: View {
    /// Nil until the song is fetched, or when it can't be; the card then shows
    /// the result's title and artist without actions.
    let song: Song?
    let fallbackTitle: String?
    let fallbackArtist: String?
    let isPractice: Bool
    let player: BandleClipPlayer
    let onOpenInPlayer: (Song) -> Void

    @State private var showAddToPlaylist = false
    @ScaledMetric(relativeTo: .body) private var artworkSize: CGFloat = 64
    private let favorites = FavoritesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.l) {
            Label(
                isPractice ? String(localized: "Practice Song") : String(localized: "Today's Song"),
                systemImage: "music.note"
            )
            .font(AM.Font.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(Color.appAccent)

            HStack(spacing: AM.Spacing.m) {
                RemoteArtworkImage(
                    url: song.flatMap { PlaybackRowState.shared.displayImageURL(for: $0, variant: .row) },
                    cornerRadius: AM.Radius.thumb,
                    fixedDisplaySize: CGSize(width: artworkSize, height: artworkSize)
                )
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(.rect(cornerRadius: AM.Radius.thumb))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                    Text(song?.title ?? fallbackTitle ?? String(localized: "Answer unavailable"))
                        .font(AM.Font.rowTitle)
                        .lineLimit(2)
                    if let artist = song?.displayArtist ?? fallbackArtist {
                        Text(artist)
                            .font(AM.Font.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let song {
                    if favorites.isAvailable {
                        favoriteButton(for: song)
                    }
                    Menu {
                        SongActionsMenuItems(song: song) {
                            showAddToPlaylist = true
                        }
                    } label: {
                        Label(String(localized: "More Actions"), systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("Bandle.RevealedSong.Menu")
                }
            }

            if let song {
                if song.audioURL != nil {
                    BandleSongPlaybackRow(player: player)
                }
                Button(String(localized: "Open in Player"), systemImage: "play.rectangle") {
                    onOpenInPlayer(song)
                }
                .buttonStyle(.bordered)
                .buttonSizing(.flexible)
                .accessibilityIdentifier("Bandle.RevealedSong.OpenInPlayer")
            }
        }
        .padding(AM.Spacing.l)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Bandle.RevealedSong")
        .sheet(isPresented: $showAddToPlaylist) {
            if let song {
                AddToPlaylistSheet(song: song)
            }
        }
    }

    private func favoriteButton(for song: Song) -> some View {
        let isFavorite = favorites.isFavorite(song.id)
        return Button(
            isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Favorite"),
            systemImage: isFavorite ? "star.fill" : "star"
        ) {
            favorites.toggle(songID: song.id)
            (isFavorite ? AppHaptic.selection : AppHaptic.success).play()
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(isFavorite ? Color.appAccent : .secondary)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityIdentifier("Bandle.RevealedSong.Favorite")
    }
}
