import SwiftUI

/// The song rows of `PlaylistDetailView`.
///
/// Its own view with value inputs, compared with `.equatable()`, so the
/// screen's frequent passes (each 2pt of the pull-to-find, the collapsing
/// title) stop here instead of rebuilding every row's identity. Each element
/// yields exactly one view, the row with its separator, so SwiftUI can take
/// the row identities from the ids instead of running every row's body to
/// count what it produces.
struct PlaylistSongList: View, Equatable {
    let playlist: Playlist
    let songs: [Song]
    var rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin

    /// Not the synthesized `==`: `Song` and `Playlist` compare by id only, so
    /// the detail fetch landing with the artists, durations and artwork that
    /// the list DTOs lack would compare equal and leave the rows stale.
    /// Compares what a row draws instead.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.playlist.id == rhs.playlist.id
            && lhs.rowHorizontalPadding == rhs.rowHorizontalPadding
            && lhs.songs.count == rhs.songs.count
            && zip(lhs.songs, rhs.songs).allSatisfy { RowContent($0) == RowContent($1) }
    }

    private struct RowContent: Equatable {
        let id: String
        let title: String
        let metadata: Song.RowMetadata
        let absolutePath: String?
        let cloudflareID: String?
        let coverPath: String?
        let coverCloudflareID: String?
        let userUploaded: Bool?

        init(_ song: Song) {
            id = song.id
            title = song.title
            metadata = song.rowMetadata
            absolutePath = song.absolutePath
            cloudflareID = song.cloudflareID
            coverPath = song.coverArt?.absolutePath
            coverCloudflareID = song.coverArt?.cloudflareId
            userUploaded = song.userUploaded
        }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(songs.enumerated().map { PositionedPlaylistSong(offset: $0.offset, song: $0.element) }) { item in
                VStack(spacing: 0) {
                    Button {
                        play(item.song)
                    } label: {
                        PlaylistRow(song: item.song, showsArtwork: true, horizontalPadding: rowHorizontalPadding)
                            .contentShape(Rectangle())
                            .songRowAccessibility(song: item.song) {
                                play(item.song)
                            }
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                    .accessibilityHint("Starts playback.")
                    .accessibilityIdentifier("PlaylistDetail.song.\(item.offset).\(item.song.id)")
                    if item.offset < songs.count - 1 {
                        Divider().padding(.leading, rowHorizontalPadding + 60)
                    }
                }
            }
        }
    }

    private func play(_ song: Song) {
        AppHaptic.selection.play()
        PlaylistPlayback.play(song, from: playlist, context: songs)
    }
}
