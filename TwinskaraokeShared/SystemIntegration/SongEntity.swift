#if os(iOS)
import AppIntents
import Foundation

struct SongEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Song"
    static let defaultQuery = SongEntityQuery()
    var id: String
    @Property(title: "Title") var title: String
    @Property(title: "Cover Artists") var coverArtists: [String]
    @Property(title: "Original Artists") var originalArtists: [String]
    @Property(title: "Duration") var duration: Int
    var artworkFilename: String?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(coverArtists.joined(separator: ", "))") }
    init(_ song: WidgetSong) {
        id = song.id; title = song.title; coverArtists = song.coverArtists
        originalArtists = song.originalArtists; duration = song.duration; artworkFilename = song.artworkFilename
    }
    #if !WIDGET_EXTENSION
    init(_ song: Song) {
        self.init(WidgetSong(id: song.id, title: song.title, artist: song.displayArtist, originalArtists: song.originalArtists ?? [], coverArtists: song.coverArtists ?? [], duration: song.duration))
    }
    #endif
}
struct SongEntityQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [SongEntity] {
        let snapshot = WidgetSnapshotStore().readPlayback()
        var seen = Set<String>()
        return ([snapshot.song].compactMap { $0 } + snapshot.queue).filter { seen.insert($0.id).inserted }.map(SongEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [SongEntity] {
        #if WIDGET_EXTENSION
        return try await suggestedEntities().filter { identifiers.contains($0.id) }
        #else
        return try await KaraokeAPIClient.fetchSongs(ids: identifiers).map(SongEntity.init)
        #endif
    }
    func entities(matching string: String) async throws -> [SongEntity] {
        #if WIDGET_EXTENSION
        return try await suggestedEntities().filter { $0.title.localizedCaseInsensitiveContains(string) || $0.coverArtists.joined().localizedCaseInsensitiveContains(string) }
        #else
        return try await KaraokeAPIClient.searchSongs(query: string, pageSize: 25).map(SongEntity.init)
        #endif
    }
}
#endif
