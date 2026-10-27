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
