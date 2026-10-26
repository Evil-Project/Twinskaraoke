import Foundation
import Network
import Testing
@testable import Twinskaraoke_Watch_App

@Suite("Durable watch downloads")
@MainActor
struct WatchDownloadsTests {
    @Test("A completion during relaunch inventory remains ready while an interrupted transfer fails")
    func completionDuringInventory() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let completed = WatchDownloads.Entry(song: UITestFixtures.song(id: "completed", title: "Completed", artist: "Artist", duration: 1))
        let interrupted = WatchDownloads.Entry(song: UITestFixtures.song(id: "interrupted", title: "Interrupted", artist: "Artist"))
        try JSONEncoder().encode([completed, interrupted]).write(to: root.appendingPathComponent("manifest.json"))
        let downloads = WatchDownloads(directory: root, sessionConfiguration: .ephemeral)
        let pending = Set(downloads.entries.map(\.transferID))
        let staged = root.appendingPathComponent("audio.wav")
        try wav().write(to: staged)
        await downloads.complete(transferID: completed.transferID.uuidString, stagedURL: staged)
        downloads.reconcileInterruptedTransfers(pending: pending, running: [])
        #expect(downloads.entry(for: completed.id)?.status == .ready)
        #expect(downloads.localURL(for: completed.id) != nil)
        #expect(downloads.entry(for: interrupted.id)?.status == .failed)
    }

    @Test("Validated audio and metadata survive relaunch and remain outside cache eviction")
    func offlineRelaunch() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let song = UITestFixtures.song(id: "offline", title: "Offline song", artist: "Artist", duration: 1)
        let entry = WatchDownloads.Entry(song: song)
        try JSONEncoder().encode([entry]).write(to: root.appendingPathComponent("manifest.json"))
        let downloads = WatchDownloads(directory: root)
        let staged = root.appendingPathComponent("audio.wav")
        try wav().write(to: staged)
        await downloads.complete(transferID: entry.transferID.uuidString, stagedURL: staged)
        #expect(downloads.entry(for: song.id)?.status == .ready)
        #expect(downloads.sizeBytes > 44)
        let restored = WatchDownloads(directory: root)
        #expect(restored.songs == [song])
        let local = try #require(restored.localURL(for: song.id))
        #expect(FileManager.default.fileExists(atPath: local.path))
        #expect(!WatchDownloads.directory.path.contains("/Caches/"))
        restored.removeAll()
        #expect(restored.songs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: local.path))
    }

    @Test("An invalid download stays retryable instead of appearing offline-ready")
    func badAudio() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = WatchDownloads.Entry(song: UITestFixtures.song(id: "bad", title: "Bad", artist: "Artist"))
        try JSONEncoder().encode([entry]).write(to: root.appendingPathComponent("manifest.json"))
        let downloads = WatchDownloads(directory: root)
        let staged = root.appendingPathComponent("response.html")
        try Data("<html>Unauthorized</html>".utf8).write(to: staged)
        await downloads.complete(transferID: entry.transferID.uuidString, stagedURL: staged)
        #expect(downloads.entry(for: entry.id)?.status == .failed)
        #expect(downloads.entry(for: entry.id)?.error != nil)
        #expect(downloads.localURL(for: entry.id) == nil)
    }

    @Test("A late download cannot recreate content removed on sign-out")
    func lateCompletion() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var entry = WatchDownloads.Entry(song: UITestFixtures.song(id: "old-account", title: "Old", artist: "Artist", duration: 1))
        entry.status = .failed
        try JSONEncoder().encode([entry]).write(to: root.appendingPathComponent("manifest.json"))
        let downloads = WatchDownloads(directory: root)
        downloads.removeAll()
        let staged = root.appendingPathComponent("late.wav")
        try wav().write(to: staged)
        await downloads.complete(transferID: entry.transferID.uuidString, stagedURL: staged)
        #expect(downloads.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #expect(downloads.localURL(for: entry.id) == nil)
    }

    @Test("Missing saved audio is reported as a retryable download after launch")
    func missingFile() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var entry = WatchDownloads.Entry(song: UITestFixtures.song(id: "missing", title: "Missing", artist: "Artist"))
        entry.status = .ready
        try JSONEncoder().encode([entry]).write(to: root.appendingPathComponent("manifest.json"))
        let downloads = WatchDownloads(directory: root)
        #expect(downloads.entry(for: entry.id)?.status == .failed)
        #expect(downloads.songs.isEmpty)
    }

    @Test("A download resolves missing audio metadata and completes the URLSession delegate pipeline")
    func resolvedTransfer() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        let server = try WatchDownloadHTTPFixture()
        let port = try await server.start()
        defer { server.listener.cancel() }
        let partial = UITestFixtures.song(id: "resolve", title: "Song", artist: "Artist", duration: 1)
        let full = Song(id: partial.id, title: partial.title, duration: 1,
            absolutePath: "http://127.0.0.1:\(port)/audio.wav", cloudflareID: nil,
            coverArt: nil, originalArtists: nil, coverArtists: nil, userUploaded: nil, oss: nil)
        let downloads = WatchDownloads(directory: root, sessionConfiguration: config, loadSong: { _ in full })
        downloads.download(partial)
        let end = Date().addingTimeInterval(10)
        while downloads.entry(for: partial.id)?.status != .ready,
              downloads.entry(for: partial.id)?.status != .failed, Date() < end {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(downloads.entry(for: partial.id)?.error == nil)
        #expect(downloads.entry(for: partial.id)?.status == .ready)
        #expect(downloads.localURL(for: partial.id) != nil)
        #expect(downloads.entry(for: partial.id)?.song.audioURL == full.audioURL)
        downloads.removeAll()
    }

    @Test("Legacy audio-suffix downloads migrate and remain available")
    func migrateLegacyDownload() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let song = UITestFixtures.song(id: "legacy", title: "Legacy", artist: "Artist", duration: 1)
        var entry = WatchDownloads.Entry(song: song)
        entry.status = .ready
        try JSONEncoder().encode([entry]).write(to: root.appendingPathComponent("manifest.json"))
        let legacy = root.appendingPathComponent(SongStorageKey.component(for: song.id) + ".audio")
        try wav().write(to: legacy)
        let restored = WatchDownloads(directory: root)
        #expect(restored.entry(for: song.id)?.status == .ready)
        #expect(restored.localURL(for: song.id)?.pathExtension == "mp3")
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("Cancelling metadata resolution prevents a late download from returning")
    func cancelledResolution() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let song = UITestFixtures.song(id: "pending", title: "Pending", artist: "Artist")
        let downloads = WatchDownloads(directory: root, loadSong: { _ in
            try await Task.sleep(for: .milliseconds(100))
            return song
        })
        downloads.download(song)
        #expect(downloads.entry(for: song.id)?.status == .waiting)
        downloads.removeAll()
        try await Task.sleep(for: .milliseconds(150))
        #expect(downloads.entries.isEmpty)
    }

    @Test("Account storage counts and clears saved, cached and orphaned audio")
    func accountStorage() async throws {
        let root = try directory()
        let cache = try directory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cache)
        }
        let song = UITestFixtures.song(id: "storage", title: "Stored", artist: "Artist", duration: 1)
        let entry = WatchDownloads.Entry(song: song)
        try JSONEncoder().encode([entry]).write(to: root.appendingPathComponent("manifest.json"))
        let downloads = WatchDownloads(directory: root, sessionConfiguration: .ephemeral)
        let bytes = wav()
        let staged = root.appendingPathComponent("staged.wav")
        try bytes.write(to: staged)
        await downloads.complete(transferID: entry.transferID.uuidString, stagedURL: staged)
        try Data(repeating: 1, count: 4096).write(to: root.appendingPathComponent("orphan.mp3"))
        try Data(repeating: 1, count: 2048).write(to: cache.appendingPathComponent("cached.mp3"))
        #expect(downloads.storageBytes == Int64(bytes.count + 4096))
        #expect(AudioManager.downloadedAudioSizeBytes(downloads: downloads, cacheDirectory: cache) == Int64(bytes.count + 6144))
        let revision = downloads.storageRevision
        AudioManager.shared.clearAllDownloadedAudio(downloads: downloads, cacheDirectory: cache)
        #expect(downloads.storageRevision > revision)
        #expect(downloads.entries.isEmpty)
        #expect(AudioManager.downloadedAudioSizeBytes(downloads: downloads, cacheDirectory: cache) == 0)
        let late = root.appendingPathComponent("late.wav")
        try bytes.write(to: late)
        await downloads.complete(transferID: entry.transferID.uuidString, stagedURL: late)
        #expect(downloads.storageBytes == 0)
        #expect(downloads.entries.isEmpty)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func wav() -> Data {
        // One second of PCM: local, deterministic audio validation with no server.
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func word(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func number(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        text("RIFF"); number(16036); text("WAVEfmt "); number(16)
        word(1); word(1); number(8000); number(16000); word(2); word(16)
        text("data"); number(16000); data.append(Data(repeating: 0, count: 16000))
        return data
    }
}

nonisolated private final class WatchDownloadHTTPFixture: @unchecked Sendable {
    let listener: NWListener
    init() throws { listener = try NWListener(using: .tcp, on: .any) }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                let audio = Self.wav()
                var response = Data("HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nContent-Length: \(audio.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(audio)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    private static func wav() -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); integer(UInt32(16036)); text("WAVEfmt "); integer(UInt32(16))
        integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(8000)); integer(UInt32(16000))
        integer(UInt16(2)); integer(UInt16(16)); text("data"); integer(UInt32(16000))
        data.append(Data(repeating: 0, count: 16000))
        return data
    }
}
