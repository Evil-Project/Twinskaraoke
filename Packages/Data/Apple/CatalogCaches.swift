import Foundation

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
