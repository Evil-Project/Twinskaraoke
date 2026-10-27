import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Shimeji resource pack lifecycle")
struct ShimejiResourceManagerTests {
    @Test("Removing the pack survives the settings screen appearing again")
    func removalSuppressesTheAutomaticDownload() throws {
        try withManager { manager, packDirectory in
            try writeManifest(in: packDirectory)
            manager.loadFromDiskIfAvailable()
            #expect(manager.state == .ready)

            manager.deleteDownloadedPack()
            #expect(manager.state == .notDownloaded)
            #expect(manager.wasRemovedByUser)

            // What the settings screen does on every appearance. Starting a
            // download would move the state off .notDownloaded synchronously.
            manager.downloadIfNeeded()
            #expect(manager.state == .notDownloaded)
            #expect(!FileManager.default.fileExists(atPath: packDirectory.path))
        }
    }

    @Test("A pack that is back on disk re-arms the automatic download")
    func loadingFromDiskClearsTheRemovalFlag() throws {
        try withManager { manager, packDirectory in
            manager.deleteDownloadedPack()
            #expect(manager.wasRemovedByUser)

            try writeManifest(in: packDirectory)
            manager.loadFromDiskIfAvailable()
            #expect(manager.state == .ready)
            #expect(!manager.wasRemovedByUser)
        }
    }

    private func withManager(
        _ body: (ShimejiResourceManager, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let packDirectory = root.appendingPathComponent("ShimejiPack", isDirectory: true)
        let suiteName = "ShimejiResourceManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        try body(ShimejiResourceManager(packDirectory: packDirectory, defaults: defaults), packDirectory)
    }

    private func writeManifest(in packDirectory: URL) throws {
        try FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)
        let manifest = ShimejiManifest(
            formatVersion: 1,
            packName: "Test Pack",
            characters: [
                ShimejiCharacterDefinition(
                    id: "test",
                    displayName: "Test",
                    folder: "test",
                    frameSize: 64,
                    anchor: ShimejiAnchor(x: 32, y: 64),
                    actions: [
                        ShimejiActionKind.stand.rawValue: ShimejiActionDefinition(
                            frames: ["stand.png"],
                            frameDuration: 0.2,
                            loop: true
                        ),
                    ]
                ),
            ]
        )
        try JSONEncoder().encode(manifest).write(
            to: packDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }
}
