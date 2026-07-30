import Combine
import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Downloads, extracts, caches, and exposes the Shimeji resource pack.
/// The pack is intentionally hosted remotely rather than bundled, so new
/// characters/actions can ship without an app update — see manifest.json's
/// `formatVersion` for the on-disk contract this expects.
@MainActor
final class ShimejiResourceManager: NSObject, ObservableObject {
    static let shared = ShimejiResourceManager()

    static let packURL = URL(string: "https://sb.sillyprootsoda.com/shimeji_nwero.zip")!
    // TODO: Replace with project-controlled distribution URL and add SHA-256 verification
    // Expected checksum would be validated after download before extraction
    static let expectedSHA256: String? = nil

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case extracting
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .notDownloaded
    @Published private(set) var manifest: ShimejiManifest?

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    private lazy var packDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ShimejiPack", isDirectory: true)
    }()

    private var manifestURL: URL {
        packDirectory.appendingPathComponent("manifest.json")
    }

    override init() {
        super.init()
        loadFromDiskIfAvailable()
    }

    /// Called at app launch (and whenever the experiment toggle turns on) to
    /// pick up an already-downloaded pack without re-fetching it.
    func loadFromDiskIfAvailable() {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(ShimejiManifest.self, from: data)
            state = .ready
        } catch {
            DebugLogger.log("Shimeji: failed to load cached manifest — \(error)", category: .cache)
        }
    }

    func imageURL(character: ShimejiCharacterDefinition, frame: String) -> URL {
        packDirectory
            .appendingPathComponent("Characters", isDirectory: true)
            .appendingPathComponent(character.folder, isDirectory: true)
            .appendingPathComponent(frame)
    }

    func download() {
        guard case .notDownloaded = state else { return }
        state = .downloading(progress: 0)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300 // 5 minutes for large pack download
        let session = URLSession(configuration: config)
        let task = session.downloadTask(with: ShimejiResourceManager.packURL) { [weak self] tempURL, response, error in
            Task { @MainActor in
                self?.handleDownloadCompletion(tempURL: tempURL, response: response, error: error)
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Task { @MainActor in
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }
        downloadTask = task
        task.resume()
    }

    func retry() {
        state = .notDownloaded
        download()
    }

    func cancelDownload() {
        progressObservation = nil
        downloadTask?.cancel()
        downloadTask = nil
        if case .downloading = state {
            state = .notDownloaded
        }
    }

    private func handleDownloadCompletion(tempURL: URL?, response: URLResponse?, error: Error?) {
        progressObservation = nil
        downloadTask = nil

        if let error {
            state = .failed(error.localizedDescription)
            return
        }

        // Validate HTTP status before processing
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                state = .failed("Download failed with HTTP \(httpResponse.statusCode)")
                return
            }
        }

        guard let tempURL else {
            state = .failed("Download failed.")
            return
        }

        state = .extracting

        // Move off the temp file synchronously before the completion handler's
        // scope releases it, then hop to a background queue for extraction.
        let stagedZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("shimeji_nwero_\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: tempURL, to: stagedZip)
        } catch {
            state = .failed("Couldn't stage the download: \(error.localizedDescription)")
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let manifest = try await self.extractAndLoad(zipURL: stagedZip)
                await MainActor.run {
                    self.manifest = manifest
                    self.state = .ready
                }
            } catch {
                await MainActor.run {
                    self.state = .failed("Couldn't set up the pack: \(error.localizedDescription)")
                }
            }
            try? FileManager.default.removeItem(at: stagedZip)
        }
    }

    private nonisolated func extractAndLoad(zipURL: URL) async throws -> ShimejiManifest {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let packDirectory = base.appendingPathComponent("ShimejiPack", isDirectory: true)

        // Extract into a fresh temp location first, then swap it in — avoids
        // ever leaving a half-extracted pack behind if this fails partway.
        let stagingDirectory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try ShimejiZipReader.extract(zipURL: zipURL, to: stagingDirectory)

        let stagedManifestURL = stagingDirectory.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: stagedManifestURL)
        let manifest = try JSONDecoder().decode(ShimejiManifest.self, from: manifestData)
        guard manifest.formatVersion == 1 else {
            throw NSError(
                domain: "Shimeji",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This pack needs a newer version of the app."]
            )
        }

        // Application Support isn't guaranteed to exist on disk yet on a
        // fresh install — FileManager just hands back the URL it *would*
        // use, without creating it. Moving into a directory whose parent
        // doesn't exist fails, so make sure it's really there first.
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        if fm.fileExists(atPath: packDirectory.path) {
            try fm.removeItem(at: packDirectory)
        }
        try fm.moveItem(at: stagingDirectory, to: packDirectory)

        // Invalidate cached sprite images after successful extraction
        await MainActor.run {
            #if canImport(UIKit)
            ShimejiSpriteView.invalidateImageCache()
            #endif
        }

        return manifest
    }

    func deleteDownloadedPack() {
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation = nil
        try? FileManager.default.removeItem(at: packDirectory)
        manifest = nil
        state = .notDownloaded
        #if canImport(UIKit)
        ShimejiSpriteView.invalidateImageCache()
        #endif
    }
}
