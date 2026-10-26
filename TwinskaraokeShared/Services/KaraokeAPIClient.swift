import Foundation
import os

extension Notification.Name {
  nonisolated static let karaokeSessionExpired = Notification.Name("KaraokeSessionExpired")
}

actor UploadedSongMetadataCache {
  private struct Entry: Sendable {
    let songs: [Song]
    let coveredIDs: Set<String>
    let expiresAt: Date
  }

  private let lifetime: TimeInterval
  private var cachedValue: Entry?
  private var inFlight: (id: UUID, task: Task<[Song], Error>)?
  private var epoch = 0

  init(lifetime: TimeInterval) {
    self.lifetime = lifetime
  }

  func value(
    for requestedIDs: Set<String>,
    at now: Date = Date(),
    loader: @escaping @Sendable () async throws -> [Song]
  ) async throws -> [Song] {
    guard !requestedIDs.isEmpty else { return [] }
    if let cachedValue,
      cachedValue.expiresAt > now,
      requestedIDs.isSubset(of: cachedValue.coveredIDs)
    {
      return cachedValue.songs.filter { requestedIDs.contains($0.id) }
    }

    let startEpoch = epoch
    let request: (id: UUID, task: Task<[Song], Error>)
    if let inFlight {
      request = inFlight
    } else {
      let id = UUID()
      let task = Task { try await loader() }
      request = (id, task)
      inFlight = request
    }

    do {
      let songs = try await request.task.value
      guard epoch == startEpoch else { throw CancellationError() }
      let coveredIDs = (cachedValue?.coveredIDs ?? [])
        .union(requestedIDs)
        .union(songs.map(\.id))
      cachedValue = Entry(
        songs: songs,
        coveredIDs: coveredIDs,
        expiresAt: now.addingTimeInterval(lifetime)
      )
      if inFlight?.id == request.id {
        inFlight = nil
      }
      return songs.filter { requestedIDs.contains($0.id) }
    } catch {
      if inFlight?.id == request.id {
        inFlight = nil
      }
      throw error
    }
  }

  func invalidate() {
    cachedValue = nil
    inFlight?.task.cancel()
    inFlight = nil
    epoch &+= 1
  }
}
actor PlaylistDetailCache {
  private struct Entry: Sendable {
    let data: Data
    let expiresAt: Date
  }

  private let lifetime: TimeInterval
  private var entries: [String: Entry] = [:]
  private var inFlight: [String: (id: UUID, task: Task<Data, Error>)] = [:]
  private var generations: [String: Int] = [:]
  private var epoch = 0

  init(lifetime: TimeInterval) {
    self.lifetime = lifetime
  }

  func data(
    for playlistID: String,
    at now: Date = Date(),
    loader: @escaping @Sendable () async throws -> Data
  ) async throws -> Data {
    entries = entries.filter { $0.value.expiresAt > now }
    if let entry = entries[playlistID] {
      return entry.data
    }

    let startGeneration = generations[playlistID, default: 0]
    let startEpoch = epoch
    let request: (id: UUID, task: Task<Data, Error>)
    if let existing = inFlight[playlistID] {
      request = existing
    } else {
      let id = UUID()
      let task = Task { try await loader() }
      request = (id, task)
      inFlight[playlistID] = request
    }

    do {
      let data = try await request.task.value
      if epoch == startEpoch, generations[playlistID, default: 0] == startGeneration {
        entries[playlistID] = Entry(data: data, expiresAt: now.addingTimeInterval(lifetime))
      }
      if inFlight[playlistID]?.id == request.id {
        inFlight[playlistID] = nil
      }
      return data
    } catch {
      if inFlight[playlistID]?.id == request.id {
        inFlight[playlistID] = nil
      }
      throw error
    }
  }

  func invalidate(playlistID: String) {
    entries[playlistID] = nil
    generations[playlistID, default: 0] &+= 1
    inFlight[playlistID]?.task.cancel()
    inFlight[playlistID] = nil
  }

  func invalidateAll() {
    entries.removeAll()
    inFlight.values.forEach { $0.task.cancel() }
    inFlight.removeAll()
    epoch &+= 1
  }
}
actor FavoriteCatalogMetadataCache {
  private struct Entry: Sendable {
    let key: String
    let songs: [Song]
    let expiresAt: Date
  }

  private let lifetime: TimeInterval
  private var cachedValue: Entry?
  private var inFlight: [String: (id: UUID, task: Task<[Song], Error>)] = [:]
  private var epoch = 0

  init(lifetime: TimeInterval) {
    self.lifetime = lifetime
  }

  func value(
    for ids: [String],
    at now: Date = Date(),
    loader: @escaping @Sendable () async throws -> [Song]
  ) async throws -> [Song] {
    guard !ids.isEmpty else { return [] }
    let key = ids.sorted().joined(separator: ",")
    if let cachedValue, cachedValue.key == key, cachedValue.expiresAt > now {
      return cachedValue.songs
    }

    let startEpoch = epoch
    let request: (id: UUID, task: Task<[Song], Error>)
    if let existing = inFlight[key] {
      request = existing
    } else {
      let id = UUID()
      let task = Task { try await loader() }
      request = (id, task)
      inFlight[key] = request
    }

    do {
      let songs = try await request.task.value
      guard epoch == startEpoch else { throw CancellationError() }
      cachedValue = Entry(key: key, songs: songs, expiresAt: now.addingTimeInterval(lifetime))
      if inFlight[key]?.id == request.id {
        inFlight[key] = nil
      }
      return songs
    } catch {
      if inFlight[key]?.id == request.id {
        inFlight[key] = nil
      }
      throw error
    }
  }

  func invalidate() {
    cachedValue = nil
    inFlight.values.forEach { $0.task.cancel() }
    inFlight.removeAll()
    epoch &+= 1
  }
}
actor FavoriteSongsCache {
  private struct Entry: Sendable {
    let songs: [Song]
    let expiresAt: Date
  }

  private let lifetime: TimeInterval
  private var cachedValue: Entry?
  private var inFlight: (id: UUID, task: Task<[Song], Error>)?
  private var epoch = 0

  init(lifetime: TimeInterval) {
    self.lifetime = lifetime
  }

  func value(
    at now: Date = Date(),
    loader: @escaping @Sendable () async throws -> [Song]
  ) async throws -> [Song] {
    if let cachedValue, cachedValue.expiresAt > now {
      return cachedValue.songs
    }

    let startEpoch = epoch
    let request: (id: UUID, task: Task<[Song], Error>)
    if let inFlight {
      request = inFlight
    } else {
      let id = UUID()
      let task = Task { try await loader() }
      request = (id, task)
      inFlight = request
    }

    do {
      let songs = try await request.task.value
      guard epoch == startEpoch else { throw CancellationError() }
      cachedValue = Entry(songs: songs, expiresAt: now.addingTimeInterval(lifetime))
      if inFlight?.id == request.id {
        inFlight = nil
      }
      return songs
    } catch {
      if inFlight?.id == request.id {
        inFlight = nil
      }
      throw error
    }
  }

  func invalidate() {
    cachedValue = nil
    inFlight?.task.cancel()
    inFlight = nil
    epoch &+= 1
  }
}

nonisolated enum KaraokeAPIClient {
  enum APIError: Error {
    case invalidURL
    case invalidBody
    case invalidResponse
    case httpStatus(Int)
    case decodeFailed
  }

  private static let favoriteMetadataLogger = Logger(
    subsystem: "com.xiaoyuan151.Twinskaraoke",
    category: "Network"
  )
  private static let uploadedSongMetadataCache = UploadedSongMetadataCache(lifetime: 60)
  private static let playlistDetailCache = PlaylistDetailCache(lifetime: 60)
  private static let favoriteCatalogMetadataCache = FavoriteCatalogMetadataCache(lifetime: 60)
  private static let favoriteSongsCache = FavoriteSongsCache(lifetime: 60)

  static func trendingSongs(days: Int = 7, take: Int? = nil) async throws -> [Song] {
    try await trendingSongs(days: String(days), take: take)
  }

  static func trendingSongs(days: String, take: Int? = nil) async throws -> [Song] {
    var queryItems = [
      URLQueryItem(name: "days", value: days),
    ]
    if let take {
      queryItems.append(URLQueryItem(name: "take", value: String(take)))
    }
    let request = try request(path: "/api/explore/trendings", queryItems: queryItems)
    let data = try await data(for: request)
    return try decode([Song].self, from: data)
  }

  static func playlists(
    startIndex: Int,
    pageSize: Int,
    isSetlist: Bool,
    sortDescending: Bool
  ) async throws -> [Playlist] {
    let request = try request(
      path: "/api/playlists",
      queryItems: [
        URLQueryItem(name: "startIndex", value: String(startIndex)),
        URLQueryItem(name: "pageSize", value: String(pageSize)),
        URLQueryItem(name: "search", value: ""),
        URLQueryItem(name: "sortBy", value: ""),
        URLQueryItem(name: "sortDescending", value: sortDescending ? "True" : "False"),
        URLQueryItem(name: "isSetlist", value: isSetlist ? "True" : "False"),
        URLQueryItem(name: "year", value: "0"),
      ]
    )
    let data = try await data(for: request)
    return try decodePlaylists(from: data)
  }

  static func publicPlaylists(
    startIndex: Int,
    pageSize: Int,
    sortDescending: Bool = true
  ) async throws -> [Playlist] {
    let request = try request(
      path: "/api/playlist/public",
      queryItems: [
        URLQueryItem(name: "startIndex", value: String(startIndex)),
        URLQueryItem(name: "pageSize", value: String(pageSize)),
        URLQueryItem(name: "search", value: ""),
        URLQueryItem(name: "sortBy", value: "UpdatedAt"),
        URLQueryItem(name: "sortDescending", value: sortDescending ? "True" : "False"),
      ]
    )
    let data = try await data(for: request)
    return try decodePlaylists(from: data)
  }

  static func playlistDetail(id: String) async throws -> PlaylistDetail {
    let data = try await playlistDetailData(id: id)
    return try decode(PlaylistDetail.self, from: data)
  }

  static func playlistSongs(id: String) async throws -> [Song] {
    if id == Playlist.favoritesID {
      return try await favoriteSongs()
    }
    let songs = applyingPersistedOrder(try await playlistDetail(id: id).songListDTOs)
    return try await hydratePlaylistUploadedSongs(songs)
  }

  private static func hydratePlaylistUploadedSongs(_ songs: [Song]) async throws -> [Song] {
    guard CredentialStore.token != nil else { return songs }
    let missingDurationIDs = songs.filter { $0.duration <= 0 }.map(\.id)
    guard !missingDurationIDs.isEmpty else { return songs }

    do {
      let uploadedMetadata = try await uploadedSongs(matching: missingDurationIDs)
      return hydratingFavorites(
        songs,
        canonicalSongs: [],
        uploadedSongs: uploadedMetadata
      )
    } catch {
      try rethrowIfCancelled(error)
      favoriteMetadataLogger.error(
        "Playlist uploaded metadata fetch failed: \(String(describing: error), privacy: .public)"
      )
      return songs
    }
  }

  static func playlistSongCount(id: String) async throws -> Int? {
    let data = try await playlistDetailData(id: id)
    if let playlist = try? decode(Playlist.self, from: data) {
      return playlist.songListDTOs?.count ?? max(playlist.songCount, 0)
    }
    return SongPayloadDecoder.decodeSongs(from: data)?.count
  }

  static func favoriteSongs() async throws -> [Song] {
    try await favoriteSongsCache.value {
      let request = try request(
        path: "/api/favorites/type",
        queryItems: [URLQueryItem(name: "type", value: "0")]
      )
      let data = try await data(for: request)
      guard let songs = SongPayloadDecoder.decodeSongs(from: data) else {
        throw APIError.decodeFailed
      }
      return try await hydrateFavoriteSongs(applyingPersistedOrder(songs))
    }
  }

  private static func hydrateFavoriteSongs(_ songs: [Song]) async throws -> [Song] {
    guard !songs.isEmpty else { return songs }
    async let canonicalResult = favoriteCatalogMetadata(ids: songs.map(\.id))
    async let uploadedResult = favoriteUploadedMetadata(ids: songs.map(\.id))
    return hydratingFavorites(
      songs,
      canonicalSongs: try await canonicalResult,
      uploadedSongs: try await uploadedResult
    )
  }

  private static func favoriteCatalogMetadata(ids: [String]) async throws -> [Song] {
    do {
      return try await favoriteCatalogMetadataCache.value(for: ids) {
        try await fetchSongs(ids: ids)
      }
    } catch {
      try rethrowIfCancelled(error)
      favoriteMetadataLogger.error(
        "Favorite catalog metadata fetch failed: \(String(describing: error), privacy: .public)"
      )
      return []
    }
  }

  private static func favoriteUploadedMetadata(ids: [String]) async throws -> [Song] {
    do {
      return try await uploadedSongs(matching: ids)
    } catch {
      try rethrowIfCancelled(error)
      favoriteMetadataLogger.error(
        "Favorite uploaded metadata fetch failed: \(String(describing: error), privacy: .public)"
      )
      return []
    }
  }

  private static func rethrowIfCancelled(_ error: Error) throws {
    if error is CancellationError || (error as? URLError)?.code == .cancelled {
      throw error
    }
  }

  static func hydratingFavorites(
    _ songs: [Song],
    canonicalSongs: [Song],
    uploadedSongs: [Song]
  ) -> [Song] {
    var canonicalByID = Dictionary(
      canonicalSongs.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for uploadedSong in uploadedSongs {
      canonicalByID[uploadedSong.id] = uploadedSong
    }
    return songs.map { favorite in
      guard let canonical = canonicalByID[favorite.id] else { return favorite }
      return favorite.fillingMissingMetadata(from: canonical)
    }
  }

  static func uploadedSongs(matching ids: [String]) async throws -> [Song] {
    try await uploadedSongMetadataCache.value(for: Set(ids)) {
      try await uploadedSongs()
    }
  }

  static func uploadedSongs() async throws -> [Song] {
    let data = try await data(for: uploadedSongsRequest())
    guard let songs = SongPayloadDecoder.decodeSongs(from: data) else {
      throw APIError.decodeFailed
    }
    return songs
  }

  static func uploadedSongsRequest(readToken: () throws -> String? = CredentialStore.requestToken) throws -> URLRequest {
    var request = try request(path: "/api/user/songs", readToken: readToken)
    request.httpMethod = "GET"
    return request
  }

  static func songSuggestions(take: Int) async throws -> [Song] {
    let request = try request(
      path: "/api/user/suggestions",
      queryItems: [URLQueryItem(name: "take", value: String(take))]
    )
    let data = try await data(for: request)
    return try decode([Song].self, from: data)
  }

  static func latestReleases(pageSize: Int = 48, take: Int = 24) async throws -> [Song] {
    let data = try await songSearchData(
      query: "",
      pageSize: pageSize,
      sortBy: "CreatedAt",
      sortDescending: true
    )
    let decoded = try decodeSongSearchResults(from: data)
    let filtered = decoded.filter {
      !$0.title.localizedCaseInsensitiveContains("Temporary Stream Audio")
    }
    return Array((filtered.isEmpty ? decoded : filtered).prefix(take))
  }

  static func fetchSong(id: String) async throws -> Song {
    let request = try request(pathSegments: ["api", "songs", id])
    let data = try await data(for: request)
    if let song = try? decode(Song.self, from: data) { return song }
    if let envelope = try? decode(FavoriteSongEnvelope.self, from: data), let song = envelope.song { return song }
    if let songs = SongPayloadDecoder.decodeSongs(from: data), let song = songs.first { return song }
    if let response = try? decode(SearchResponse.self, from: data), let song = response.items.first { return song }
    if let songs = try? decode([Song].self, from: data), let song = songs.first { return song }
    if let song = songFromJSONObject(data) { return song }
    throw APIError.decodeFailed
  }

  static func fetchSongs(ids: [String]) async throws -> [Song] {
    var seenIDs = Set<String>()
    let uniqueIDs = ids.filter { id in
      seenIDs.insert(id).inserted
    }
    guard !uniqueIDs.isEmpty else { return [] }
    let request = try songsByIDsRequest(uniqueIDs)
    let data = try await data(for: request, retriesNonIdempotentRequest: true)
    guard let songs = SongPayloadDecoder.decodeSongs(from: data) else {
      throw APIError.decodeFailed
    }
    return songs
  }

  static func songsByIDsRequest(_ ids: [String], readToken: () throws -> String? = CredentialStore.requestToken) throws -> URLRequest {
    var request = try request(path: "/api/songs/by-ids", readToken: readToken)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(ids)
    return request
  }

  private static func songFromJSONObject(_ data: Data) -> Song? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let candidate: [String: Any]?
    if let song = json["song"] as? [String: Any] { candidate = song }
    else if let song = json["songData"] as? [String: Any] { candidate = song }
    else if let song = json["songDTO"] as? [String: Any] { candidate = song }
    else if let song = json["data"] as? [String: Any] { candidate = song }
    else if let song = json["item"] as? [String: Any] { candidate = song }
    else { candidate = json }
    guard let dict = candidate else { return nil }
    guard let id = dict["id"] as? String,
          let title = dict["title"] as? String
    else { return nil }
    let duration: Int
    if let d = dict["duration"] as? Int { duration = d }
    else if let d = dict["duration"] as? Double { duration = Int(d) }
    else if let d = dict["duration"] as? String, let parsed = Int(d) { duration = parsed }
    else { duration = 0 }
    let absolutePath = dict["absolutePath"] as? String
    let cloudflareID = dict["cloudflareId"] as? String ?? dict["cloudflareID"] as? String
    let coverArt: Media? = {
      if let media = dict["coverArt"] as? [String: Any] {
        return Media(absolutePath: media["absolutePath"] as? String)
      }
      return nil
    }()
    let originalArtists = dict["originalArtists"] as? [String]
    let coverArtists = dict["coverArtists"] as? [String]
    let userUploaded = dict["userUploaded"] as? Bool
    return Song(
      id: id,
      title: title,
      duration: duration,
      absolutePath: absolutePath,
      cloudflareID: cloudflareID,
      coverArt: coverArt,
      originalArtists: originalArtists,
      coverArtists: coverArtists,
      userUploaded: userUploaded,
      oss: dict["oss"] as? String,
      order: dict["order"] as? Int
    )
  }

  static func randomSongs() async throws -> [Song] {
    var request = try request(
      path: "/api/songs/random",
      queryItems: [
        URLQueryItem(
          name: "_",
          value: String(Int(Date().timeIntervalSince1970 * 1000))
        ),
      ]
    )
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    let data = try await data(for: request)
    do {
      return try decode([Song].self, from: data)
    } catch {
      throw APIError.decodeFailed
    }
  }

  static func searchSongs(query: String, pageSize: Int) async throws -> [Song] {
    let data = try await songSearchData(query: query, pageSize: pageSize)
    return try decodeSongSearchResults(from: data)
  }

  /// One page of song search results, with the server's total when it sends
  /// one. `page` is 1-based, as the API counts it.
  static func searchSongPage(query: String, page: Int, pageSize: Int) async throws -> SongSearchPage {
    let data = try await songSearchData(query: query, page: page, pageSize: pageSize)
    if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
      return SongSearchPage(songs: decoded.items, totalCount: decoded.totalCount)
    }
    if let decoded = SongPayloadDecoder.decodeSongs(from: data) {
      return SongSearchPage(songs: decoded, totalCount: nil)
    }
    throw APIError.decodeFailed
  }

  static func searchSongItems(query: String, pageSize: Int) async throws -> [SearchSongItem] {
    let data = try await songSearchData(query: query, pageSize: pageSize)
    if let decoded = try? JSONDecoder().decode(SearchResponseRoot.self, from: data) {
      return decoded.items
    }
    throw APIError.decodeFailed
  }

  private static func songSearchData(
    query: String,
    page: Int = 1,
    pageSize: Int,
    sortBy: String? = nil,
    sortDescending: Bool? = nil
  ) async throws -> Data {
    var body: [String: Any] = [
      "page": max(1, page),
      "pageSize": pageSize,
      "search": query,
    ]
    if let sortBy {
      body["sortBy"] = sortBy
    }
    if let sortDescending {
      body["sortDescending"] = sortDescending
    }
    let request = try jsonRequest(
      path: "/api/songs",
      body: body
    )
    return try await data(for: request, retriesNonIdempotentRequest: true)
  }

  static func playlistDetailData(id: String) async throws -> Data {
    try await playlistDetailCache.data(for: id) {
      let request = try request(pathSegments: ["api", "playlist", id])
      return try await data(for: request)
    }
  }
  static func invalidatePlaylistDetail(id: String) async {
    await playlistDetailCache.invalidate(playlistID: id)
  }
  static func invalidateFavoriteSongs() async {
    await favoriteSongsCache.invalidate()
  }
  static func invalidateAccountScopedCaches() async {
    await playlistDetailCache.invalidateAll()
    await favoriteCatalogMetadataCache.invalidate()
    await favoriteSongsCache.invalidate()
    await uploadedSongMetadataCache.invalidate()
  }

  private static func decodeSongSearchResults(from data: Data) throws -> [Song] {
    if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
      return decoded.items
    }
    if let decoded = SongPayloadDecoder.decodeSongs(from: data) {
      return decoded
    }
    throw APIError.decodeFailed
  }

  static func decodePlaylists(from data: Data) throws -> [Playlist] {
    let decoder = JSONDecoder()
    if let items = try? decoder.decode([PlaylistListItem].self, from: data) {
      return items.map { $0.asPlaylist() }
    }
    if let items = try? decoder.decode([Playlist].self, from: data) { return items }
    throw APIError.decodeFailed
  }

  static func restoringRequest<Value: Sendable>(
    _ operation: @Sendable () async throws -> Value
  ) async throws -> Value {
    for attempt in 0...2 {
      do { return try await operation() }
      catch {
        try Task.checkCancellation()
        let retryable: Bool
        switch error {
        case is CredentialStore.StoreError: retryable = true
        case let error as URLError:
          retryable = [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                       .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
        case APIError.httpStatus(let status): retryable = status == 429 || status >= 500
        default: retryable = false
        }
        DebugLogger.log("Playlist request failed: \(error); attempt=\(attempt + 1), retry=\(retryable && attempt < 2)", category: .network)
        guard retryable, attempt < 2 else { throw error }
        try await Task.sleep(for: .seconds(attempt + 1))
      }
    }
    throw APIError.decodeFailed
  }

  static func jsonRequest(path: String, body: [String: Any]) throws -> URLRequest {
    guard JSONSerialization.isValidJSONObject(body) else {
      throw APIError.invalidBody
    }
    var request = try request(path: path)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }
  static func jsonArrayRequest(
    pathSegments: [String],
    body: [[String: Any]]
  ) throws -> URLRequest {
    guard JSONSerialization.isValidJSONObject(body) else {
      throw APIError.invalidBody
    }
    var request = try request(pathSegments: pathSegments)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }
  static func applyingPersistedOrder(_ songs: [Song]) -> [Song] {
    songs.enumerated()
      .sorted { lhs, rhs in
        let left = lhs.element.order ?? Int.max
        let right = rhs.element.order ?? Int.max
        return left == right ? lhs.offset < rhs.offset : left < right
      }
      .map(\.element)
  }

  static func songMovePayload(
    songID: String,
    from oldOrder: Int,
    to newOrder: Int
  ) -> [[String: Any]] {
    [
      [
        "songId": songID,
        "userAudioId": NSNull(),
        "order": 0,
        "oldOrder": oldOrder,
        "newOrder": newOrder,
      ]
    ]
  }


  static func request(
    path: String,
    queryItems: [URLQueryItem] = [],
    readToken: () throws -> String? = CredentialStore.requestToken
  ) throws -> URLRequest {
    guard var components = URLComponents(string: StorageHost.api) else {
      throw APIError.invalidURL
    }
    components.path = path
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else {
      throw APIError.invalidURL
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    if let token = try readToken() {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    return request
  }

  static func request(
    pathSegments: [String],
    queryItems: [URLQueryItem] = [],
    readToken: () throws -> String? = CredentialStore.requestToken
  ) throws -> URLRequest {
    guard !pathSegments.isEmpty, var components = URLComponents(string: StorageHost.api) else {
      throw APIError.invalidURL
    }
    let encodedSegments = try pathSegments.map { segment -> String in
      guard !segment.isEmpty,
            segment != ".",
            segment != "..",
            let encoded = segment.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed)
      else {
        throw APIError.invalidURL
      }
      return encoded
    }
    components.percentEncodedPath = "/" + encodedSegments.joined(separator: "/")
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    if let token = try readToken() {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    return request
  }

  private static let pathSegmentAllowed: CharacterSet = {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/%?#")
    return allowed
  }()

  static func data(
    for request: URLRequest,
    retriesNonIdempotentRequest: Bool = false,
    allowsRetry: Bool = true
  ) async throws -> Data {
    let maxRetries = 3
    let baseDelay: Duration = .milliseconds(500)
    let canRetry = allowsRetry && (retriesNonIdempotentRequest || isIdempotent(request))

    for attempt in 0..<maxRetries {
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
          if httpResponse.statusCode == 401,
            let authorization = request.value(forHTTPHeaderField: "Authorization"),
            let currentToken = CredentialStore.token,
            authorization == "Bearer \(currentToken)"
          {
            NotificationCenter.default.post(name: .karaokeSessionExpired, object: nil,
                                            userInfo: ["requestToken": currentToken])
          }

          if canRetry && shouldRetry(statusCode: httpResponse.statusCode) && attempt < maxRetries - 1 {
            let delay: Duration
            if httpResponse.statusCode == 429,
              let retryAfter = retryAfterInterval(from: httpResponse)
            {
              delay = .seconds(retryAfter)
            } else {
              delay = backoffDelay(attempt: attempt, baseDelay: baseDelay)
            }
            try await Task.sleep(for: delay)
            continue
          }
          throw APIError.httpStatus(httpResponse.statusCode)
        }
        return data
      } catch let error as URLError {

        if canRetry && shouldRetry(urlError: error) && attempt < maxRetries - 1 {
          try await Task.sleep(for: backoffDelay(attempt: attempt, baseDelay: baseDelay))
          continue
        }
        throw error
      } catch {

        throw error
      }
    }

    throw APIError.invalidResponse
  }

  private static func isIdempotent(_ request: URLRequest) -> Bool {
    guard let method = request.httpMethod?.uppercased() else { return true }
    return method == "GET" || method == "HEAD" || method == "PUT" || method == "DELETE"
  }
  private static func backoffDelay(attempt: Int, baseDelay: Duration) -> Duration {
    baseDelay * Double(1 << attempt) + baseDelay * Double.random(in: 0 ... 0.5)
  }
  private static let maxRetryAfterInterval: TimeInterval = 300

  private static func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
    guard let value = response.value(forHTTPHeaderField: "Retry-After")?
      .trimmingCharacters(in: .whitespaces)
    else { return nil }
    if let seconds = TimeInterval(value), seconds >= 0 {
      return min(seconds, maxRetryAfterInterval)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = formatter.date(from: value) else { return nil }
    return min(max(0, date.timeIntervalSinceNow), maxRetryAfterInterval)
  }

  private static func shouldRetry(statusCode: Int) -> Bool {

    return statusCode == 408 ||
           statusCode == 429 ||
           ((500..<600).contains(statusCode) && statusCode != 501)
  }

  private static func shouldRetry(urlError: URLError) -> Bool {

    switch urlError.code {
    case .timedOut,
         .cannotConnectToHost,
         .networkConnectionLost,
         .resourceUnavailable,
         .badServerResponse:
      return true
    default:
      return false
    }
  }

  private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    try JSONDecoder().decode(type, from: data)
  }
}
