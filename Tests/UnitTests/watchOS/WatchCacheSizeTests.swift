import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

/// Backs the Storage row on the Account screen, which is the only thing that
/// tells a listener why the watch is filling up.
@Suite("Watch audio cache size")
struct WatchCacheSizeTests {
    @Test("Size is the total of every cached file")
    func sumsCachedFiles() throws {
        let directory = try makeCacheDirectory(fileSizes: [1024, 2048, 512])
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(AudioManager.cacheSizeBytes(in: directory) == 3584)
    }

    @Test("An empty cache reports zero rather than failing")
    func emptyCacheIsZero() throws {
        let directory = try makeCacheDirectory(fileSizes: [])
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(AudioManager.cacheSizeBytes(in: directory) == 0)
    }

    /// The directory is created lazily on first download, so the Account screen
    /// can ask before it exists.
    @Test("A missing cache directory reports zero rather than failing")
    func missingDirectoryIsZero() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)")

        #expect(AudioManager.cacheSizeBytes(in: missing) == 0)
    }

    private func makeCacheDirectory(fileSizes: [Int]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, size) in fileSizes.enumerated() {
            try Data(repeating: 0x41, count: size)
                .write(to: directory.appendingPathComponent("song-\(index).mp3"))
        }
        return directory
    }
}
