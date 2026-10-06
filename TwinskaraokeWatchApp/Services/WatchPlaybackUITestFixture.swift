#if DEBUG
import Foundation

/// Exercises the real cache, AVAsset validation, audio session and AVPlayer
/// paths without relying on a signed-in account or a remote media server.
@MainActor
enum WatchPlaybackUITestFixture {
    static func prepareIfNeeded() {
        guard AppRuntime.isUITestMode else { return }
        let downloaded = ProcessInfo.processInfo.arguments.contains("-UITestDownloadedAudio")
        let standalone = downloaded || ProcessInfo.processInfo.arguments.contains("-UITestLocalAudio")
        let lease = CompanionPlayback.Lease(owner: standalone ? .watch : .phone)
        CompanionPlayback.saveLease(lease)
        UserDefaults.standard.removeObject(forKey: "nk.watch.relinquishedLease")
        UserDefaults.standard.removeObject(forKey: "nk.watch.localPlayback")
        guard standalone else { return }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioCache")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rate = 16_000
        let frames = rate * 30
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); integer(UInt32(36 + frames * 2)); text("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1))
        integer(UInt32(rate)); integer(UInt32(rate * 2)); integer(UInt16(2)); integer(UInt16(16))
        text("data"); integer(UInt32(frames * 2))
        for frame in 0..<frames {
            integer(Int16(sin(Double(frame) * 2 * .pi * 440 / Double(rate)) * 1500))
        }
        var saved: [WatchDownloads.Entry] = []
        let titles = ["Wake Me Up Before You Go-Go", "Hero", "Fixture Song"]
        for (index, id) in ["watch-ui-song-1", "watch-ui-song-2", "watch-ui-song-3"].enumerated() {
            let path = directory.appendingPathComponent("\(SongStorageKey.component(for: id)).mp3")
            if downloaded {
                try? FileManager.default.removeItem(at: path)
                let stored = WatchDownloads.directory.appendingPathComponent(SongStorageKey.component(for: id) + ".wav")
                try? data.write(to: stored, options: .atomic)
                var entry = WatchDownloads.Entry(song: UITestFixtures.song(id: id, title: titles[index], artist: "Artist", duration: 30))
                entry.status = .ready
                entry.fileExtension = "wav"
                saved.append(entry)
            } else {
                try? data.write(to: path, options: .atomic)
            }
        }
        if downloaded, let manifest = try? JSONEncoder().encode(saved) {
            try? manifest.write(to: WatchDownloads.directory.appendingPathComponent("manifest.json"), options: .atomic)
        }
    }
}
#endif
