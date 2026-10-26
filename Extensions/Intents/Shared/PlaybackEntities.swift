// MARK: - SongEntity

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

// MARK: - PlaylistEntity

#if os(iOS)
import AppIntents
import Foundation

struct PlaylistEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    static let defaultQuery = PlaylistEntityQuery()
    var id: String
    @Property(title: "Name") var name: String
    @Property(title: "Song Count") var songCount: Int
    @Property(title: "Personal Playlist") var isPersonal: Bool
    var artworkFilename: String?
    var artworkFilenames: [String]?
    var route: AppRoute {
        id == "__radio__" ? .radio : .playlist(id)
    }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(songCount) songs") }
    init(_ value: WidgetPlaylist) {
        id = value.id; name = value.name; songCount = value.songCount
        isPersonal = value.isPersonal; artworkFilename = value.artworkFilename
        artworkFilenames = value.artworkFilenames
    }
}
struct PlaylistEntityQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [PlaylistEntity] {
        #if WIDGET_EXTENSION
        return WidgetSnapshotStore().readLibrary().suggestions.map(PlaylistEntity.init)
        #else
        return await PlaylistIntentRepository.suggestions().map { PlaylistEntity(PlaylistIntentRepository.snapshot($0)) }
        #endif
    }
    func entities(for identifiers: [String]) async throws -> [PlaylistEntity] {
        let suggestions = try await suggestedEntities() + Self.launchers
        var result: [PlaylistEntity] = []
        for id in identifiers {
            if let entity = suggestions.first(where: { $0.id == id }) { result.append(entity); continue }
            #if !WIDGET_EXTENSION
            if id.hasPrefix("__") { continue }
            if let detail = try? await KaraokeAPIClient.playlistDetail(id: id) {
                result.append(PlaylistEntity(WidgetPlaylist(id: detail.id, name: detail.name, songCount: detail.songListDTOs.count)))
            }
            #endif
        }
        return result
    }
    func entities(matching string: String) async throws -> [PlaylistEntity] {
        #if WIDGET_EXTENSION
        return try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
        #else
        return try await PlaylistIntentRepository.search(string).map { PlaylistEntity(PlaylistIntentRepository.snapshot($0)) }
        #endif
    }
    static var launchers: [PlaylistEntity] {
        [WidgetPlaylist(id: "__downloads__", name: String(localized: "Downloaded Songs")),
         WidgetPlaylist(id: "__radio__", name: String(localized: "Live Radio"))].map(PlaylistEntity.init)
    }
}

#endif
