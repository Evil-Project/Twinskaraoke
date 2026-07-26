import Foundation

enum LyricsCacheVariant: String {
    case original
    case translated
}

enum LyricsCacheStore {
    private static let fm = FileManager.default
    // Entries are KB-sized JSON documents, so I/O stays synchronous on the
    // caller; the lock serializes clear() with loads/saves so a save can't
    // write into a directory clear() just deleted.
    private static let ioLock = NSLock()

    nonisolated static let cacheDirectory: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LyricsCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func load(songID: String, variant: LyricsCacheVariant) -> [LyricLine]? {
        let url = cacheFileURL(for: songID, variant: variant)
        ioLock.lock()
        let cached = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(CachedLyricsDocument.self, from: $0) }
        if let cached, cached.lines.isEmpty {
            try? fm.removeItem(at: url)
        }
        ioLock.unlock()
        guard let cached, !cached.lines.isEmpty else {
            return nil
        }
        CacheManager.shared.recordAccess(for: url)
        return cached.lines.map { $0.asLyricLine() }
    }

    static func save(_ lyrics: [LyricLine], songID: String, variant: LyricsCacheVariant) {
        let url = cacheFileURL(for: songID, variant: variant)
        guard !lyrics.isEmpty else {
            ioLock.lock()
            try? fm.removeItem(at: url)
            ioLock.unlock()
            return
        }
        let document = CachedLyricsDocument(
            savedAt: Date(),
            lines: lyrics.map(CachedLyricLine.init)
        )
        guard let data = try? JSONEncoder().encode(document) else { return }
        ioLock.lock()
        try? data.write(to: url, options: .atomic)
        ioLock.unlock()
        CacheManager.shared.recordAccess(for: url)
        CacheManager.shared.enforceLyricsCacheLimits()
    }

    static func clear() {
        ioLock.lock()
        try? fm.removeItem(at: cacheDirectory)
        try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        ioLock.unlock()
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
