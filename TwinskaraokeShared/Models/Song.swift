import Foundation

nonisolated struct LossyArray<Element: Decodable>: Decodable, Sendable where Element: Sendable {
  let elements: [Element]

  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var items: [Element] = []
    while !container.isAtEnd {
      if let value = try? container.decode(Element.self) {
        items.append(value)
      } else {
        _ = try? container.decode(DiscardedDecodable.self)
      }
    }
    elements = items
  }
}

nonisolated private struct DiscardedDecodable: Decodable, Sendable {}

nonisolated enum SongCountText {
  static func songs(_ count: Int) -> String {
    count == 1 ? "1 song" : "\(count) songs"
  }
}

nonisolated struct Song: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let duration: Int
  let absolutePath: String?
  let cloudflareID: String?
  let coverArt: Media?
  let originalArtists: [String]?
  let coverArtists: [String]?
  let userUploaded: Bool?
  let oss: String?

  enum CodingKeys: String, CodingKey {
    case id, title, duration, absolutePath, coverArt, originalArtists, coverArtists, userUploaded, oss
    case cloudflareID = "cloudflareId"
  }

  init(
    id: String,
    title: String,
    duration: Int,
    absolutePath: String?,
    cloudflareID: String?,
    coverArt: Media?,
    originalArtists: [String]?,
    coverArtists: [String]?,
    userUploaded: Bool?,
    oss: String? = nil
  ) {
    self.id = id
    self.title = title
    self.duration = duration
    self.absolutePath = absolutePath
    self.cloudflareID = cloudflareID
    self.coverArt = coverArt
    self.originalArtists = originalArtists
    self.coverArtists = coverArtists
    self.userUploaded = userUploaded
    self.oss = oss
  }

  init(
    id: String,
    title: String,
    duration: Int,
    absolutePath: String?,
    coverArt: SongMedia?,
    coverArtists: [String]?,
    originalArtists: [String]?,
    cloudflareId: String?,
    userUploaded: Bool?,
    oss: String? = nil
  ) {
    self.init(
      id: id,
      title: title,
      duration: duration,
      absolutePath: absolutePath,
      cloudflareID: cloudflareId,
      coverArt: coverArt,
      originalArtists: originalArtists,
      coverArtists: coverArtists,
      userUploaded: userUploaded,
      oss: oss
    )
  }

  var cloudflareId: String? { cloudflareID }

  var imageURL: URL? {
    imageURL(variant: .card)
  }

  var fullHDImageURL: URL? {
    imageURL(variant: .fullHD)
  }

  var thumbnailURL: URL? {
    imageURL(variant: .thumbnail)
  }

  var rowImageURL: URL? {
    imageURL(variant: .row)
  }

  var heroImageURL: URL? {
    imageURL(variant: .hero)
  }

  var downloadCoverImageURL: URL? {
    guard hasOwnArtwork else { return nil }
    return ArtworkURLBuilder.imageURL(
      cloudflareID: cloudflareID,
      path: coverArt?.absolutePath,
      variant: .download
    )
  }

  private func imageURL(variant: ArtworkImageVariant) -> URL? {
    ArtworkURLBuilder.imageURL(
      cloudflareID: cloudflareID,
      path: coverArt?.absolutePath,
      variant: variant
    ) ?? neuroFallbackImageURL
  }

  var hasOwnArtwork: Bool {
    cloudflareID != nil || coverArt?.absolutePath != nil
  }

  private static let neuroArtistNames: Set<String> = ["Neuro", "Neuro v1", "Neuro v2"]

  private var neuroFallbackImageURL: URL? {
    #if os(watchOS)
    return nil
    #else
    let artists = coverArtists ?? []
    let isNeuro = artists.contains { Self.neuroArtistNames.contains($0) }
    guard isNeuro || userUploaded == true else { return nil }
    return FallbackArtProvider.shared.url(for: id)
    #endif
  }

  var fallbackArtCredit: String? {
    #if os(watchOS)
    return nil
    #else
    guard !hasOwnArtwork else { return nil }
    let artists = coverArtists ?? []
    let isNeuro = artists.contains { Self.neuroArtistNames.contains($0) }
    guard isNeuro || userUploaded == true else { return nil }
    return FallbackArtProvider.shared.art(for: id)?.artistName
    #endif
  }

  var audioURL: URL? {
    if let path = Self.normalizedAudioPath(absolutePath) {
      let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
      return URL(string: "\(StorageHost.base)/\(cleanPath)")
    }
    // User-uploaded songs deliver their audio path in `oss`; it can contain
    // spaces and other characters that need percent-encoding.
    guard let oss = Self.normalizedAudioPath(oss) else { return nil }
    let cleanPath = oss.hasPrefix("/") ? String(oss.dropFirst()) : oss
    let encodedPath = cleanPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanPath
    return URL(string: "\(StorageHost.base)/\(encodedPath)")
  }

  private static func normalizedAudioPath(_ path: String?) -> String? {
    guard let path else { return nil }
    let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  var displayTitle: String {
    let artists = originalArtists?.joined(separator: ", ") ?? ""
    return artists.isEmpty ? title : "\(title) - \(artists)"
  }

  var displayCoverArtist: String {
    coverArtists?.joined(separator: ", ") ?? ""
  }

  var displayArtist: String {
    let original = originalArtists?.filter { !$0.isEmpty }.joined(separator: ", ") ?? ""
    let cover = coverArtists?.filter { !$0.isEmpty }.joined(separator: ", ") ?? ""
    switch (original.isEmpty, cover.isEmpty) {
    case (false, false): return "\(original) · Cover by \(cover)"
    case (false, true): return original
    case (true, false): return "Cover by \(cover)"
    case (true, true):
      let apiProvidedArtists = originalArtists != nil || coverArtists != nil
      return apiProvidedArtists ? "Unknown Artist" : ""
    }
  }

  var artistName: String {
    if let originals = originalArtists, !originals.isEmpty {
      return originals.joined(separator: ", ")
    }
    return coverArtists?.joined(separator: ", ") ?? "Unknown Artist"
  }

  var hasArtistMetadata: Bool {
    let original = originalArtists?.filter { !$0.isEmpty } ?? []
    let cover = coverArtists?.filter { !$0.isEmpty } ?? []
    return !original.isEmpty || !cover.isEmpty
  }

  var durationText: String {
    guard duration > 0 else { return "" }
    let m = duration / 60
    let s = duration % 60
    return String(format: "%d:%02d", m, s)
  }

  static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }

}

nonisolated struct Playlist: Codable, Identifiable, Hashable, Sendable {
  static let favoritesID = "__favorites__"
  let id: String
  let name: String
  let songCount: Int
  let media: PlaylistMedia?
  let mosaicMedia: [Media]?
  let songListDTOs: [Song]?
  var isPersonal: Bool = false

  private enum CodingKeys: String, CodingKey {
    case id, name, songCount, count, media, mosaicMedia, songListDTOs, items, songs, favorites
    case isPersonal
  }

  init(
    id: String,
    name: String,
    songCount: Int,
    media: PlaylistMedia? = nil,
    mosaicMedia: [Media]?,
    songListDTOs: [Song]?,
    isPersonal: Bool = false
  ) {
    self.id = id
    self.name = name
    self.songCount = songCount
    self.media = media
    self.mosaicMedia = mosaicMedia
    self.songListDTOs = songListDTOs
    self.isPersonal = isPersonal
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    if let value = try? container.decode(Int.self, forKey: .songCount) {
      songCount = value
    } else {
      songCount = (try? container.decode(Int.self, forKey: .count)) ?? 0
    }
    media = try? container.decodeIfPresent(PlaylistMedia.self, forKey: .media)
    mosaicMedia =
      (try? container.decodeIfPresent(LossyArray<Media>.self, forKey: .mosaicMedia)?.elements)
      ?? (try? container.decodeIfPresent([Media].self, forKey: .mosaicMedia))
    songListDTOs =
      Self.decodeSongs(from: container, forKey: .songListDTOs)
      ?? Self.decodeSongs(from: container, forKey: .items)
      ?? Self.decodeSongs(from: container, forKey: .songs)
      ?? Self.decodeSongs(from: container, forKey: .favorites)
    isPersonal = (try? container.decodeIfPresent(Bool.self, forKey: .isPersonal)) ?? false
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(songCount, forKey: .songCount)
    try container.encodeIfPresent(media, forKey: .media)
    try container.encodeIfPresent(mosaicMedia, forKey: .mosaicMedia)
    try container.encodeIfPresent(songListDTOs, forKey: .songListDTOs)
    try container.encode(isPersonal, forKey: .isPersonal)
  }

  var imageURL: URL? {
    imageURL(variant: .card)
  }

  var thumbnailURL: URL? {
    imageURL(variant: .thumbnail)
  }

  var rowImageURL: URL? {
    imageURL(variant: .row)
  }

  func imageURL(variant: ArtworkImageVariant) -> URL? {
    if let url = ArtworkURLBuilder.imageURL(
      cloudflareID: media?.cloudflareId,
      path: media?.absolutePath,
      variant: variant
    ) {
      return url
    }
    if let media = mosaicMedia?.first,
      let url = ArtworkURLBuilder.imageURL(
        cloudflareID: media.cloudflareId,
        path: media.absolutePath,
        variant: variant
      )
    {
      return url
    }
    guard let song = songListDTOs?.first else { return nil }
    switch variant {
    case .row:
      return song.rowImageURL
    case .thumbnail:
      return song.thumbnailURL
    case .hero:
      return song.heroImageURL
    case .fullHD:
      return song.fullHDImageURL
    default:
      return song.imageURL
    }
  }

  var isFavorites: Bool { id == Self.favoritesID }

  var isSessionOwned: Bool { isFavorites || isPersonal }

  var songCountText: String {
    SongCountText.songs(songCount)
  }

  static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.id == rhs.id }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  private static func decodeSongs(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> [Song]? {
    if let decoded = try? container.decode(LossyArray<Song>.self, forKey: key) {
      return decoded.elements
    }
    if let decoded = try? container.decode([Song].self, forKey: key) {
      return decoded
    }
    if let decoded = try? container.decode(LossyArray<FavoriteSongEnvelope>.self, forKey: key) {
      let songs = decoded.elements.compactMap(\.song)
      if !songs.isEmpty { return songs }
    }
    if let decoded = try? container.decode([FavoriteSongEnvelope].self, forKey: key) {
      let songs = decoded.compactMap(\.song)
      if !songs.isEmpty { return songs }
    }
    return nil
  }
}

nonisolated struct PlaylistListItem: Decodable, Identifiable, Sendable {
  let id: String
  let name: String
  let songCount: Int
  let media: PlaylistMedia?
  let mosaicMedia: [Media]?
  let songListDTOs: [Song]?

  private enum CodingKeys: String, CodingKey {
    case id, name, songCount, count, media, mosaicMedia, songListDTOs, items, songs, favorites
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    if let value = try? container.decode(Int.self, forKey: .songCount) {
      songCount = value
    } else {
      songCount = (try? container.decode(Int.self, forKey: .count)) ?? 0
    }
    media = try? container.decodeIfPresent(PlaylistMedia.self, forKey: .media)
    mosaicMedia =
      (try? container.decodeIfPresent(LossyArray<Media>.self, forKey: .mosaicMedia)?.elements)
      ?? (try? container.decodeIfPresent([Media].self, forKey: .mosaicMedia))
    songListDTOs =
      Self.decodeSongs(from: container, forKey: .songListDTOs)
      ?? Self.decodeSongs(from: container, forKey: .items)
      ?? Self.decodeSongs(from: container, forKey: .songs)
      ?? Self.decodeSongs(from: container, forKey: .favorites)
  }

  func asPlaylist() -> Playlist {
    let effectiveCount = max(songCount, songListDTOs?.count ?? 0)
    return Playlist(
      id: id,
      name: name,
      songCount: effectiveCount,
      media: media,
      mosaicMedia: mosaicMedia,
      songListDTOs: songListDTOs
    )
  }

  private static func decodeSongs(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> [Song]? {
    if let decoded = try? container.decode(LossyArray<Song>.self, forKey: key) {
      return decoded.elements
    }
    if let decoded = try? container.decode([Song].self, forKey: key) {
      return decoded
    }
    if let decoded = try? container.decode(LossyArray<FavoriteSongEnvelope>.self, forKey: key) {
      let songs = decoded.elements.compactMap(\.song)
      if !songs.isEmpty { return songs }
    }
    if let decoded = try? container.decode([FavoriteSongEnvelope].self, forKey: key) {
      let songs = decoded.compactMap(\.song)
      if !songs.isEmpty { return songs }
    }
    return nil
  }
}

nonisolated struct PlaylistMedia: Codable, Sendable {
  let cloudflareId: String?
  let absolutePath: String?
}

nonisolated struct Media: Codable, Sendable {
  let absolutePath: String?
  let cloudflareId: String?

  private enum CodingKeys: String, CodingKey {
    case absolutePath
    case cloudflareId
    case cloudflareID
  }

  init(absolutePath: String?, cloudflareId: String? = nil) {
    self.absolutePath = absolutePath
    self.cloudflareId = cloudflareId
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    absolutePath = try? container.decodeIfPresent(String.self, forKey: .absolutePath)
    cloudflareId =
      (try? container.decodeIfPresent(String.self, forKey: .cloudflareId))
      ?? (try? container.decodeIfPresent(String.self, forKey: .cloudflareID))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(absolutePath, forKey: .absolutePath)
    try container.encodeIfPresent(cloudflareId, forKey: .cloudflareId)
  }
}

typealias SongMedia = Media

nonisolated struct PlaylistDetail: Codable, Sendable {
  let id: String
  let name: String
  let songListDTOs: [Song]
}

nonisolated struct SearchResponse: Codable, Sendable {
  let items: [Song]
}

nonisolated struct SearchSongItem: Codable, Identifiable, Sendable {
  let id: String
  let title: String
  let duration: Int
  let absolutePath: String?
  let originalArtists: [String]?
  let coverArtists: [String]?
  let coverArt: SearchMedia?
  let cloudflareId: String?
  let userUploaded: Bool?
  let oss: String?

  init(
    id: String,
    title: String,
    duration: Int,
    absolutePath: String?,
    originalArtists: [String]?,
    coverArtists: [String]?,
    coverArt: SearchMedia?,
    cloudflareId: String?,
    userUploaded: Bool? = nil,
    oss: String? = nil
  ) {
    self.id = id
    self.title = title
    self.duration = duration
    self.absolutePath = absolutePath
    self.originalArtists = originalArtists
    self.coverArtists = coverArtists
    self.coverArt = coverArt
    self.cloudflareId = cloudflareId
    self.userUploaded = userUploaded
    self.oss = oss
  }

  var imageURL: URL? {
    imageURL(variant: .card)
  }

  var thumbnailURL: URL? {
    imageURL(variant: .thumbnail)
  }

  var rowImageURL: URL? {
    imageURL(variant: .row)
  }

  func imageURL(variant: ArtworkImageVariant) -> URL? {
    ArtworkURLBuilder.imageURL(
      cloudflareID: cloudflareId,
      path: coverArt?.absolutePath,
      variant: variant
    )
  }

  var originalArtistDisplay: String {
    originalArtists?.joined(separator: ", ") ?? ""
  }

  func toSong() -> Song? {
    let playableAbsolutePath = absolutePath.flatMap {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    }
    let playableOSS = oss.flatMap {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    }
    guard playableAbsolutePath != nil || playableOSS != nil else { return nil }
    return Song(
      id: id,
      title: title,
      duration: duration,
      absolutePath: playableAbsolutePath,
      coverArt: coverArt.map { SongMedia(absolutePath: $0.absolutePath) },
      coverArtists: coverArtists,
      originalArtists: originalArtists,
      cloudflareId: cloudflareId,
      userUploaded: userUploaded,
      oss: playableOSS
    )
  }

}

nonisolated struct SearchMedia: Codable, Sendable {
  let absolutePath: String
}

nonisolated struct SearchResponseRoot: Codable, Sendable {
  let items: [SearchSongItem]
}

nonisolated struct FavoriteSongEnvelope: Decodable, Sendable {
  let song: Song?

  enum CodingKeys: String, CodingKey { case song, songData, songDTO }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let decoded = try? container.decode(Song.self, forKey: .song) {
      song = decoded
    } else if let decoded = try? container.decode(Song.self, forKey: .songData) {
      song = decoded
    } else if let decoded = try? container.decode(Song.self, forKey: .songDTO) {
      song = decoded
    } else {
      song = nil
    }
  }
}

nonisolated struct SongArrayContainer: Decodable, Sendable {
  let songs: [Song]

  enum CodingKeys: String, CodingKey {
    case items, songListDTOs, songs, favorites
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    songs =
      Self.decodeSongs(from: container, forKey: .songListDTOs)
      ?? Self.decodeSongs(from: container, forKey: .items)
      ?? Self.decodeSongs(from: container, forKey: .songs)
      ?? Self.decodeSongs(from: container, forKey: .favorites)
      ?? []
  }

  private static func decodeSongs(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> [Song]? {
    if let decoded = try? container.decode(LossyArray<Song>.self, forKey: key) {
      return decoded.elements
    }
    if let decoded = try? container.decode([Song].self, forKey: key) {
      return decoded
    }
    if let decoded = try? container.decode(LossyArray<FavoriteSongEnvelope>.self, forKey: key) {
      let songs = decoded.elements.compactMap(\.song)
      if !songs.isEmpty { return songs }
    }
    if let decoded = try? container.decode([FavoriteSongEnvelope].self, forKey: key) {
      let songs = decoded.compactMap(\.song)
      if !songs.isEmpty { return songs }
    }
    return nil
  }
}

nonisolated enum SongPayloadDecoder {
  static func decodeSongs(from data: Data?) -> [Song]? {
    guard let data else { return nil }
    let decoder = JSONDecoder()

    if let wrapped = try? decoder.decode(SongArrayContainer.self, from: data),
      !wrapped.songs.isEmpty
    {
      return wrapped.songs
    }
    if let list = (try? decoder.decode(LossyArray<Song>.self, from: data))?.elements, !list.isEmpty {
      return list
    }
    if let list = try? decoder.decode([Song].self, from: data), !list.isEmpty {
      return list
    }
    if let wrapped = try? decoder.decode(LossyArray<FavoriteSongEnvelope>.self, from: data) {
      let songs = wrapped.elements.compactMap(\.song)
      if !songs.isEmpty { return songs }
    }
    if let wrapped = try? decoder.decode([FavoriteSongEnvelope].self, from: data) {
      let songs = wrapped.compactMap(\.song)
      if !songs.isEmpty { return songs }
    }
    return nil
  }
}
