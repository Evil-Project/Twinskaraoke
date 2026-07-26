import Foundation

enum LyricsCacheVariant: String {
    case original
    case translated
}

enum LyricsCacheStore {
    private static let fm = FileManager.default

    nonisolated static let cacheDirectory: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LyricsCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func load(songID: String, variant: LyricsCacheVariant) -> [LyricLine]? {
        let url = cacheFileURL(for: songID, variant: variant)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedLyricsDocument.self, from: data)
        else {
            return nil
        }
        if cached.lines.isEmpty {
            try? fm.removeItem(at: url)
            return nil
        }
        CacheManager.shared.recordAccess(for: url)
        return cached.lines.map { $0.asLyricLine() }
    }

    static func save(_ lyrics: [LyricLine], songID: String, variant: LyricsCacheVariant) {
        let url = cacheFileURL(for: songID, variant: variant)
        guard !lyrics.isEmpty else {
            try? fm.removeItem(at: url)
            return
        }
        let document = CachedLyricsDocument(
            savedAt: Date(),
            lines: lyrics.map(CachedLyricLine.init)
        )
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: url, options: .atomic)
        CacheManager.shared.recordAccess(for: url)
        CacheManager.shared.enforceLyricsCacheLimits()
    }

    static func clear() {
        try? fm.removeItem(at: cacheDirectory)
        try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private static func cacheFileURL(for songID: String, variant: LyricsCacheVariant) -> URL {
        let storageKey = SongStorageKey.component(for: songID)
        return cacheDirectory.appendingPathComponent("\(storageKey).\(variant.rawValue).json")
    }
}

private nonisolated struct CachedLyricsDocument: Codable {
    let savedAt: Date
    let lines: [CachedLyricLine]
}

private nonisolated struct CachedLyricLine: Codable {
    let time: TimeInterval
    let text: String
    let translatedText: String?

    init(_ line: LyricLine) {
        time = line.time
        text = line.text
        translatedText = line.translatedText
    }

    func asLyricLine() -> LyricLine {
        LyricLine(time: time, text: text, translatedText: translatedText)
    }
}
