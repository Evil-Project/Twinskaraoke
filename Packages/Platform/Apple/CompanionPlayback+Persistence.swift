import Foundation

nonisolated extension CompanionPlayback {
    static let leaseKey = "nk.companion.lease.v1"
    static func readLease(defaults: UserDefaults = .standard) -> Lease? {
        decode(Lease.self, from: defaults.data(forKey: leaseKey))
    }
    static func saveLease(_ lease: Lease, defaults: UserDefaults = .standard) {
        defaults.set(encode(lease), forKey: leaseKey)
    }

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
