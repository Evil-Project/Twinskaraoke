/// Row identity for the playlist song list. The offset keeps IDs unique when
/// a playlist contains the same song twice (duplicate ForEach IDs can hang
/// AttributeGraph). The content fields make the ID change when metadata
/// (artist, duration) arrives after a row was first composed: with purely
/// positional identity, an already-composed row keeps showing the stale
/// "Unknown Artist" from the artist-less list DTOs even after the detail
/// fetch lands, until the whole list is torn down and rebuilt.
struct PositionedPlaylistSong: Identifiable {
    struct ID: Hashable {
        let offset: Int
        let songID: String
        let metadata: Song.RowMetadata
    }

    let offset: Int
    let song: Song

    var id: ID {
        ID(
            offset: offset,
            songID: song.id,
            metadata: song.rowMetadata
        )
    }
}
