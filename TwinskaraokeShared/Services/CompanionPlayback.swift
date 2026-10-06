import Foundation

/// The phone grants a single audio owner; that owner publishes the complete
/// session state. Commands are transient and never replayed on reconnection.
nonisolated enum CompanionPlayback {
    static let contextKey = "nk.playback.snapshot"
    static let messageKind = "playbackCommand"
    static let messageDataKey = "nk.playback.command"
    static let replyDataKey = "nk.playback.reply"
    static let errorKey = "nk.playback.error"

    enum Owner: String, Codable, Sendable { case phone, watch }
    enum RepeatSetting: String, Codable, Sendable { case off, one, all }
    enum Action: String, Codable, Sendable {
        case play, pause, resume, next, previous, seek, radio, stopRadio, shuffle, repeatMode
        case transferToWatch, transferToPhone, replaceQueue, playNext, playLast, sleepTimer
    }

    struct Snapshot: Codable, Equatable, Sendable {
        var sessionID: UUID
        var revision: Int
        var owner: Owner
        var song: Song?
        var queue: [Song]
        var isPlaying: Bool
        var isRadio: Bool
        var radioArtworkURL: URL?
        var position: Double
        var duration: Double
        var isShuffled: Bool
        var repeatSetting: RepeatSetting
        var error: String?
        var updatedAt: Date
        var ownershipEpoch: Int = 0
        var radioStreamURL: URL?
        var accountGeneration: Int?
        var sleepDeadline: Date?
        var sleepAtEndOfSong: Bool?

        func supersedes(_ other: Snapshot?) -> Bool {
            guard let other else { return true }
            if sessionID == other.sessionID {
                if ownershipEpoch != other.ownershipEpoch { return ownershipEpoch > other.ownershipEpoch }
                return revision > other.revision
                    || (revision == other.revision && updatedAt > other.updatedAt)
            }
            return updatedAt > other.updatedAt
        }
    }

    struct Command: Codable, Sendable {
        var id: UUID = UUID()
        var sessionID: UUID?
        var clientID: UUID?
        var sequence: Int = 0
        var baseRevision: Int?
        var issuedAt: Date = Date()
        var action: Action
        var song: Song?
        var queue: [Song]?
        var position: Double?
        var streamURL: URL?
        var artworkURL: URL?
        var ownershipEpoch: Int?
        var accountGeneration: Int?
        var shuffleEnabled: Bool?
        var sleepMinutes: Int?
        var sleepAtEndOfSong: Bool?
    }

    /// Only the phone grants ownership, after stopping its audio. A watch
    /// grant remains valid offline; changing owner requires an acknowledged
    /// stop from the previous owner. Persisting this prevents app relaunches
    /// from silently creating a second audio owner.
    struct Lease: Codable, Equatable, Sendable {
        var sessionID: UUID = UUID()
        var owner: Owner = .phone
        var epoch: Int = 0

        mutating func transfer(to owner: Owner) {
            self.owner = owner
            epoch += 1
        }

        func allowsAudio(on device: Owner, relinquished: Lease? = nil) -> Bool {
            owner == device && self != relinquished
        }

        func accepts(_ snapshot: Snapshot) -> Bool {
            snapshot.sessionID == sessionID && snapshot.owner == owner
                && snapshot.ownershipEpoch == epoch
        }
    }

    static let leaseKey = "nk.companion.lease.v1"
    static func readLease(defaults: UserDefaults = .standard) -> Lease? {
        decode(Lease.self, from: defaults.data(forKey: leaseKey))
    }
    static func saveLease(_ lease: Lease, defaults: UserDefaults = .standard) {
        defaults.set(encode(lease), forKey: leaseKey)
    }

    struct CommandGate: Sendable {
        enum Decision: Equatable, Sendable { case accept, duplicate, stale }
        private var seen = Set<UUID>()
        private var clientID: UUID?
        private var sequence = 0
        private var retiredClients = Set<UUID>()
        private var latestCommandDate = Date.distantPast

        mutating func decide(
            _ command: Command,
            sessionID: UUID,
            revision: Int,
            lastPhoneChangeAt: Date
        ) -> Decision {
            if let expected = command.sessionID, expected != sessionID { return .stale }
            guard seen.insert(command.id).inserted else { return .duplicate }
            if seen.count > 200 { seen = [command.id] }
            if let incomingClient = command.clientID {
                if clientID != incomingClient {
                    guard !retiredClients.contains(incomingClient), command.issuedAt >= latestCommandDate else { return .stale }
                    if let clientID { retiredClients.insert(clientID) }
                    clientID = incomingClient
                    sequence = 0
                }
                guard command.sequence > sequence else { return .stale }
                sequence = command.sequence
            }
            if let base = command.baseRevision, base < revision,
               command.issuedAt < lastPhoneChangeAt { return .stale }
            latestCommandDate = max(latestCommandDate, command.issuedAt)
            return .accept
        }
    }

    // Keep full queues within the connectivity budget. Legacy JSON remains
    // readable for snapshots persisted by an earlier build.
    private static let compressedHeader = Data("NKP1".utf8)
    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(value) else { return nil }
        guard json.count > 4096,
              let compressed = try? (json as NSData).compressed(using: .lzfse),
              compressed.length + compressedHeader.count < json.count else { return json }
        return compressedHeader + (compressed as Data)
    }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        let json: Data
        if data.starts(with: compressedHeader) {
            guard let expanded = try? (data.dropFirst(compressedHeader.count) as NSData).decompressed(using: .lzfse) else { return nil }
            json = expanded as Data
        } else { json = data }
        return try? JSONDecoder().decode(type, from: json)
    }
}
