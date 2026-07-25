import Foundation
import os

actor UploadedSongMetadataCache {
  private struct Entry: Sendable {
    let songs: [Song]
    let coveredIDs: Set<String>
    let expiresAt: Date
  }

  private let lifetime: TimeInterval
  private var cachedValue: Entry?
  private var inFlight: (id: UUID, task: Task<[Song], Error>)?

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
      let coveredIDs = (cachedValue?.coveredIDs ?? []).union(requestedIDs)
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
    return decodePlaylists(from: data)
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
    return decodePlaylists(from: data)
  }

  static func playlistDetail(id: String) async throws -> PlaylistDetail {
    let data = try await playlistDetailData(id: id)
    return try decode(PlaylistDetail.self, from: data)
  }

  static func playlistSongs(id: String) async throws -> [Song] {
    if id == Playlist.favoritesID {
      return try await favoriteSongs()
    }
    let songs = try await playlistDetail(id: id).songListDTOs
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
      return playlist.songListDTOs?.count ?? (playlist.songCount > 0 ? playlist.songCount : nil)
    }
    return SongPayloadDecoder.decodeSongs(from: data)?.count
  }

  static func favoriteSongs() async throws -> [Song] {
    let request = try request(
      path: "/api/favorites/type",
      queryItems: [URLQueryItem(name: "type", value: "0")]
    )
    let data = try await data(for: request)
    let songs = SongPayloadDecoder.decodeSongs(from: data) ?? []
    return try await hydrateFavoriteSongs(songs)
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
      return try await fetchSongs(ids: ids)
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

  static func uploadedSongsRequest() throws -> URLRequest {
    var request = try request(path: "/api/user/songs")
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
    if let response = try? decode(SearchResponse.self, from: data), let song = response.items.first { return song }
    if let songs = SongPayloadDecoder.decodeSongs(from: data), let song = songs.first { return song }
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
    let data = try await data(for: request)
    guard let songs = SongPayloadDecoder.decodeSongs(from: data) else {
      throw APIError.decodeFailed
    }
    return songs
  }

  static func songsByIDsRequest(_ ids: [String]) throws -> URLRequest {
    var request = try request(path: "/api/songs/by-ids")
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
      userUploaded: userUploaded
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

  static func searchSongItems(query: String, pageSize: Int) async throws -> [SearchSongItem] {
    let data = try await songSearchData(query: query, pageSize: pageSize)
    if let decoded = try? JSONDecoder().decode(SearchResponseRoot.self, from: data) {
      return decoded.items
    }
    throw APIError.decodeFailed
  }

  private static func songSearchData(
    query: String,
    pageSize: Int,
    sortBy: String? = nil,
    sortDescending: Bool? = nil
  ) async throws -> Data {
    var body: [String: Any] = [
      "page": 1,
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
    return try await data(for: request)
  }

  private static func playlistDetailData(id: String) async throws -> Data {
    let request = try request(pathSegments: ["api", "playlist", id])
    return try await data(for: request)
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

  private static func decodePlaylists(from data: Data) -> [Playlist] {
    let decoder = JSONDecoder()
    if let items = (try? decoder.decode(LossyArray<PlaylistListItem>.self, from: data))?.elements {
      return items.map { $0.asPlaylist() }
    }
    if let items = try? decoder.decode([PlaylistListItem].self, from: data) {
      return items.map { $0.asPlaylist() }
    }
    if let items = (try? decoder.decode(LossyArray<Playlist>.self, from: data))?.elements {
      return items
    }
    if let items = try? decoder.decode([Playlist].self, from: data) {
      return items
    }
    return []
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

  static func request(
    path: String,
    queryItems: [URLQueryItem] = []
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
    if let token = CredentialStore.token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    return request
  }

  static func request(
    pathSegments: [String],
    queryItems: [URLQueryItem] = []
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
    if let token = CredentialStore.token {
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

  static func data(for request: URLRequest) async throws -> Data {
    let maxRetries = 3
    let baseDelay: UInt64 = 500_000_000

    for attempt in 0..<maxRetries {
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {

          if shouldRetry(statusCode: httpResponse.statusCode) && attempt < maxRetries - 1 {
            let delay = baseDelay * UInt64(1 << attempt)
            try await Task.sleep(nanoseconds: delay)
            continue
          }
          throw APIError.httpStatus(httpResponse.statusCode)
        }
        return data
      } catch let error as URLError {

        if shouldRetry(urlError: error) && attempt < maxRetries - 1 {
          let delay = baseDelay * UInt64(1 << attempt)
          try await Task.sleep(nanoseconds: delay)
          continue
        }
        throw error
      } catch {

        throw error
      }
    }

    throw APIError.invalidResponse
  }

  private static func shouldRetry(statusCode: Int) -> Bool {

    return statusCode == 408 ||
           statusCode == 429 ||
           statusCode >= 500
  }

  private static func shouldRetry(urlError: URLError) -> Bool {

    switch urlError.code {
    case .timedOut,
         .cannotFindHost,
         .cannotConnectToHost,
         .networkConnectionLost,
         .dnsLookupFailed,
         .notConnectedToInternet,
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
