import Foundation

nonisolated enum KaraokeAPIClient {
  enum APIError: Error, Equatable {
    case invalidURL
    case invalidBody
    case invalidResponse
    case httpStatus(Int)
    case decodeFailed
  }

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
    return try await playlistDetail(id: id).songListDTOs
  }

  static func playlistSongCount(id: String) async throws -> Int? {
    let data = try await playlistDetailData(id: id)
    if let playlist = try? decode(Playlist.self, from: data) {
      return max(playlist.songCount, playlist.songListDTOs?.count ?? 0)
    }
    return SongPayloadDecoder.decodeSongs(from: data)?.count
  }

  static func favoriteSongs() async throws -> [Song] {
    let request = try request(
      path: "/api/favorites/type",
      queryItems: [URLQueryItem(name: "type", value: "0")]
    )
    let data = try await data(for: request)
    return try decodeFavoriteSongs(from: data)
  }

  static func invalidateAccountScopedCaches() async {}

  static func decodeFavoriteSongs(from data: Data) throws -> [Song] {
    if let songs = SongPayloadDecoder.decodeSongs(from: data) {
      return songs
    }

    guard let payload = try? JSONSerialization.jsonObject(with: data) else {
      throw APIError.decodeFailed
    }
    if let items = payload as? [Any] {
      guard items.isEmpty else { throw APIError.decodeFailed }
      return []
    }
    if let container = payload as? [String: Any] {
      let supportedKeys = ["items", "songListDTOs", "songs", "favorites"]
      let presentValues = supportedKeys.compactMap { key -> Any? in
        guard container.keys.contains(key) else { return nil }
        return container[key]
      }
      guard !presentValues.isEmpty,
            let arrays = presentValues as? [[Any]],
            arrays.allSatisfy(\.isEmpty)
      else {
        throw APIError.decodeFailed
      }
      return []
    }
    throw APIError.decodeFailed
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
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let request = try request(path: "/api/songs/\(encoded)")
    let data = try await data(for: request)
    if let song = try? decode(Song.self, from: data) { return song }
    if let envelope = try? decode(FavoriteSongEnvelope.self, from: data), let song = envelope.song { return song }
    if let response = try? decode(SearchResponse.self, from: data), let song = response.items.first { return song }
    if let songs = SongPayloadDecoder.decodeSongs(from: data), let song = songs.first { return song }
    if let songs = try? decode([Song].self, from: data), let song = songs.first { return song }
    if let song = songFromJSONObject(data) { return song }
    throw APIError.decodeFailed
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
    let oss = dict["oss"] as? String
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
      oss: oss
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

  static func playlistDetailData(id: String) async throws -> Data {
    guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
      throw APIError.invalidURL
    }
    let request = try request(path: "/api/playlist/\(encodedID)")
    return try await data(for: request)
  }

  static func uploadedSongs() async throws -> [Song] {
    let request = try request(path: "/api/user/songs")
    let data = try await data(for: request)
    guard let songs = SongPayloadDecoder.decodeSongs(from: data) else {
      throw APIError.decodeFailed
    }
    return songs
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
    guard let payload = try? JSONSerialization.jsonObject(with: data),
          let rawItems = payload as? [Any]
    else {
      throw APIError.decodeFailed
    }
    if rawItems.isEmpty { return [] }

    let decoder = JSONDecoder()
    if let items = (try? decoder.decode(LossyArray<PlaylistListItem>.self, from: data))?.elements,
       !items.isEmpty
    {
      return items.map { $0.asPlaylist() }
    }
    if let items = try? decoder.decode([PlaylistListItem].self, from: data), !items.isEmpty {
      return items.map { $0.asPlaylist() }
    }
    if let items = (try? decoder.decode(LossyArray<Playlist>.self, from: data))?.elements,
       !items.isEmpty
    {
      return items
    }
    if let items = try? decoder.decode([Playlist].self, from: data), !items.isEmpty {
      return items
    }
    throw APIError.decodeFailed
  }

  static func jsonRequest(path: String, body: [String: Any]) throws -> URLRequest {
    try configureJSONRequest(
      try request(path: path),
      body: body
    )
  }

  static func jsonRequest(
    path: String,
    body: [String: Any],
    authenticationToken: String?,
    guestID: String?
  ) throws -> URLRequest {
    try configureJSONRequest(
      try request(
        path: path,
        authenticationToken: authenticationToken,
        guestID: guestID
      ),
      body: body
    )
  }

  private static func configureJSONRequest(
    _ baseRequest: URLRequest,
    body: [String: Any]
  ) throws -> URLRequest {
    guard JSONSerialization.isValidJSONObject(body) else {
      throw APIError.invalidBody
    }
    var request = baseRequest
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  static func request(
    path: String,
    queryItems: [URLQueryItem] = []
  ) throws -> URLRequest {
    var request = try baseRequest(path: path, queryItems: queryItems)
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    return request
  }

  static func request(
    pathSegments: [String],
    queryItems: [URLQueryItem] = []
  ) throws -> URLRequest {
    var request = try baseRequest(
      percentEncodedPath: path(from: pathSegments),
      queryItems: queryItems
    )
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    return request
  }

  static func request(
    path: String,
    queryItems: [URLQueryItem] = [],
    authenticationToken: String?,
    guestID: String?
  ) throws -> URLRequest {
    var request = try baseRequest(path: path, queryItems: queryItems)
    if let authenticationToken, !authenticationToken.isEmpty {
      request.setValue("Bearer \(authenticationToken)", forHTTPHeaderField: "Authorization")
    } else if let guestID, !guestID.isEmpty {
      request.setValue(guestID, forHTTPHeaderField: "x-guest-id")
    }
    return request
  }

  private static func baseRequest(
    path: String,
    queryItems: [URLQueryItem]
  ) throws -> URLRequest {
    guard var components = URLComponents(string: StorageHost.api) else {
      throw APIError.invalidURL
    }
    components.path = path
    return try request(from: components, queryItems: queryItems)
  }

  private static func baseRequest(
    percentEncodedPath: String,
    queryItems: [URLQueryItem]
  ) throws -> URLRequest {
    guard var components = URLComponents(string: StorageHost.api) else {
      throw APIError.invalidURL
    }
    components.percentEncodedPath = percentEncodedPath
    return try request(from: components, queryItems: queryItems)
  }

  private static func request(
    from components: URLComponents,
    queryItems: [URLQueryItem]
  ) throws -> URLRequest {
    var components = components
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else {
      throw APIError.invalidURL
    }
    return URLRequest(url: url)
  }

  private static func path(from segments: [String]) throws -> String {
    guard !segments.isEmpty else { throw APIError.invalidURL }
    let encodedSegments = try segments.map { segment -> String in
      guard !segment.isEmpty, segment != ".", segment != "..",
            let encoded = segment.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed)
      else {
        throw APIError.invalidURL
      }
      return encoded
    }
    return "/" + encodedSegments.joined(separator: "/")
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
