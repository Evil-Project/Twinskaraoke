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

nonisolated private struct FlexibleArtist: Decodable, Sendable {
  let name: String

  private enum CodingKeys: String, CodingKey {
    case name, artistName, displayName, title
  }

  init(from decoder: Decoder) throws {
    if let container = try? decoder.singleValueContainer(),
      let value = try? container.decode(String.self)
    {
      name = value
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    for key in [CodingKeys.name, .artistName, .displayName, .title] {
      if let value = try? container.decode(String.self, forKey: key) {
        name = value
        return
      }
    }
    throw DecodingError.dataCorrupted(
      .init(codingPath: decoder.codingPath, debugDescription: "Artist has no name")
    )
  }
}

nonisolated private struct FlexibleArtistList: Decodable, Sendable {
  let values: [String]

  init(from decoder: Decoder) throws {
    if let artist = try? FlexibleArtist(from: decoder) {
      let value = artist.name.trimmingCharacters(in: .whitespacesAndNewlines)
      values = value.isEmpty ? [] : [value]
      return
    }

    var container = try decoder.unkeyedContainer()
    var decoded: [String] = []
    while !container.isAtEnd {
      let elementDecoder = try container.superDecoder()
      guard let artist = try? FlexibleArtist(from: elementDecoder) else { continue }
      let value = artist.name.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { decoded.append(value) }
    }
    values = decoded
  }
}

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
    case cloudflareId
    case cloudflareID
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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    guard let decodedID = Self.decodeString(from: container, keys: [.id]),
      !decodedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw DecodingError.keyNotFound(
        CodingKeys.id,
        .init(codingPath: decoder.codingPath, debugDescription: "Song is missing an id")
      )
    }
    guard let decodedTitle = Self.decodeString(from: container, keys: [.title]),
      !decodedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw DecodingError.keyNotFound(
        CodingKeys.title,
        .init(codingPath: decoder.codingPath, debugDescription: "Song is missing a title")
      )
    }

    id = decodedID
    title = decodedTitle
    duration = Self.decodeDuration(from: container)
    absolutePath = Self.decodeString(from: container, keys: [.absolutePath])
    cloudflareID = Self.decodeString(from: container, keys: [.cloudflareId, .cloudflareID])
    coverArt = try? container.decodeIfPresent(Media.self, forKey: .coverArt)
    originalArtists = Self.decodeArtists(from: container, forKey: .originalArtists)
    coverArtists = Self.decodeArtists(from: container, forKey: .coverArtists)
    userUploaded = Self.decodeBool(from: container, forKey: .userUploaded)
    oss = Self.decodeString(from: container, keys: [.oss])
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(duration, forKey: .duration)
    try container.encodeIfPresent(absolutePath, forKey: .absolutePath)
    try container.encodeIfPresent(cloudflareID, forKey: .cloudflareId)
    try container.encodeIfPresent(coverArt, forKey: .coverArt)
    try container.encodeIfPresent(originalArtists, forKey: .originalArtists)
    try container.encodeIfPresent(coverArtists, forKey: .coverArtists)
    try container.encodeIfPresent(userUploaded, forKey: .userUploaded)
    try container.encodeIfPresent(oss, forKey: .oss)
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
    userUploaded: Bool?
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
      userUploaded: userUploaded
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
      cloudflareID: artworkCloudflareID,
      path: artworkPath,
      variant: .download
    )
  }

  private func imageURL(variant: ArtworkImageVariant) -> URL? {
    ArtworkURLBuilder.imageURL(
      cloudflareID: artworkCloudflareID,
      path: artworkPath,
      variant: variant
    ) ?? neuroFallbackImageURL
  }

  var hasOwnArtwork: Bool {
    artworkCloudflareID != nil || artworkPath != nil
  }

  func fillingMissingMetadata(from canonical: Song) -> Song {
    guard id == canonical.id else { return self }
    return Song(
      id: id,
      title: title,
      duration: duration > 0 ? duration : canonical.duration,
      absolutePath: Self.preferredString(absolutePath, fallback: canonical.absolutePath),
      cloudflareID: hasOwnArtwork
        ? cloudflareID
        : Self.preferredString(cloudflareID, fallback: canonical.cloudflareID),
      coverArt: hasUsableArtwork(coverArt) ? coverArt : canonical.coverArt,
      originalArtists: Self.preferredArtists(originalArtists, fallback: canonical.originalArtists),
      coverArtists: Self.preferredArtists(coverArtists, fallback: canonical.coverArtists),
      userUploaded: userUploaded ?? canonical.userUploaded,
      oss: Self.preferredString(oss, fallback: canonical.oss)
    )
  }

  private var artworkCloudflareID: String? {
    Self.preferredString(cloudflareID, fallback: coverArt?.cloudflareId)
  }

  private var artworkPath: String? {
    Self.preferredString(coverArt?.absolutePath, fallback: nil)
  }

  private func hasUsableArtwork(_ media: Media?) -> Bool {
    Self.preferredString(media?.cloudflareId, fallback: media?.absolutePath) != nil
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
    for source in [absolutePath, oss].compactMap({ $0 }) {
      if let url = Self.audioURL(from: source) { return url }
    }
    return nil
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

  private static func decodeString(
    from container: KeyedDecodingContainer<CodingKeys>,
    keys: [CodingKeys]
  ) -> String? {
    for key in keys {
      if let value = try? container.decode(String.self, forKey: key) { return value }
    }
    return nil
  }

  private static func decodeDuration(
    from container: KeyedDecodingContainer<CodingKeys>
  ) -> Int {
    if let value = try? container.decode(Int.self, forKey: .duration) {
      return max(0, value)
    }
    if let value = try? container.decode(Double.self, forKey: .duration), value.isFinite {
      return max(0, Int(value))
    }
    if let value = try? container.decode(String.self, forKey: .duration),
      let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
      parsed.isFinite
    {
      return max(0, Int(parsed))
    }
    return 0
  }

  private static func decodeArtists(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> [String]? {
    guard container.contains(key),
      (try? container.decodeNil(forKey: key)) != true
    else { return nil }
    return (try? container.decode(FlexibleArtistList.self, forKey: key))?.values
  }

  private static func decodeBool(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> Bool? {
    if let value = try? container.decode(Bool.self, forKey: key) { return value }
    if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
    if let value = try? container.decode(String.self, forKey: key) {
      switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "true", "1", "yes": return true
      case "false", "0", "no": return false
      default: return nil
      }
    }
    return nil
  }

  private static func preferredArtists(_ artists: [String]?, fallback: [String]?) -> [String]? {
    guard let artists else { return fallback }
    return artists.isEmpty ? fallback : artists
  }

  private static func preferredString(_ value: String?, fallback: String?) -> String? {
    guard let value else { return fallback }
    return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
  }

  private static func audioURL(from source: String) -> URL? {
    let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if value.hasPrefix("//") {
      return URL(string: "https:\(value)")
    }
    if let url = URL(string: value),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host != nil
    {
      return url
    }

    guard var components = URLComponents(string: StorageHost.base) else { return nil }
    let segments = value.split(separator: "/", omittingEmptySubsequences: true)
    guard !segments.isEmpty else { return nil }
    let encodedSegments = segments.map { segment in
      let decoded = String(segment).removingPercentEncoding ?? String(segment)
      return decoded.addingPercentEncoding(withAllowedCharacters: audioPathSegmentAllowed) ?? decoded
    }
    let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.percentEncodedPath = "/" + ([basePath] + encodedSegments)
      .filter { !$0.isEmpty }
      .joined(separator: "/")
    return components.url
  }

  private static let audioPathSegmentAllowed: CharacterSet = {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/%?#")
    return allowed
  }()

}

nonisolated private struct SongCollection: Decodable, Sendable {
  let songs: [Song]

  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var decoded: [Song] = []
    while !container.isAtEnd {
      let elementDecoder = try container.superDecoder()
      if let song = try? Song(from: elementDecoder) {
        decoded.append(song)
      } else if let envelope = try? FavoriteSongEnvelope(from: elementDecoder),
        let song = envelope.song
      {
        decoded.append(song)
      }
    }
    songs = decoded
  }
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
    (try? container.decode(SongCollection.self, forKey: key))?.songs
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
    let effectiveCount = songCount > 0 ? songCount : songListDTOs?.count ?? 0
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
    (try? container.decode(SongCollection.self, forKey: key))?.songs
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

  private enum CodingKeys: String, CodingKey {
    case id, name, songListDTOs, items, songs, favorites
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    songListDTOs =
      Self.decodeSongs(from: container, forKey: .songListDTOs)
      ?? Self.decodeSongs(from: container, forKey: .items)
      ?? Self.decodeSongs(from: container, forKey: .songs)
      ?? Self.decodeSongs(from: container, forKey: .favorites)
      ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(songListDTOs, forKey: .songListDTOs)
  }

  private static func decodeSongs(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> [Song]? {
    (try? container.decode(SongCollection.self, forKey: key))?.songs
  }
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
    guard let absPath = absolutePath else { return nil }
    return Song(
      id: id,
      title: title,
      duration: duration,
      absolutePath: absPath,
      coverArt: coverArt.map { SongMedia(absolutePath: $0.absolutePath) },
      coverArtists: coverArtists,
      originalArtists: originalArtists,
      cloudflareId: cloudflareId,
      userUploaded: nil
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
    (try? container.decode(SongCollection.self, forKey: key))?.songs
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
    if let list = (try? decoder.decode(SongCollection.self, from: data))?.songs, !list.isEmpty {
      return list
    }
    return nil
  }
}
