import Foundation

nonisolated enum SearchGenrePalette {
    static func index(for name: String, paletteCount: Int) -> Int? {
        guard paletteCount > 0 else { return nil }

        let normalizedName = name
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalizedName.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(paletteCount))
    }
}
