import Foundation
import Observation

#if canImport(UIKit)
    import UIKit
#endif

/// Downloads, extracts, caches, and exposes the Shimeji resource pack.
/// The pack is intentionally hosted remotely rather than bundled, so new
/// characters/actions can ship without an app update — see manifest.json's
/// `formatVersion` for the on-disk contract this expects.
@MainActor
@Observable
final class ShimejiResourceManager: NSObject {
    static let shared = ShimejiResourceManager()

    static let packURL = URL(string: "https://sb.sillyprootsoda.com/shimeji_nwero.zip")!

    private static let removedByUserKey = "nk.shimeji.packRemovedByUser"

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case extracting
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded
    private(set) var manifest: ShimejiManifest?

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    @ObservationIgnored private var installationTask: Task<Void, Never>?
    private var operationGeneration: UInt = 0

    @ObservationIgnored private let packDirectory: URL
    @ObservationIgnored private let defaults: UserDefaults

    private static var defaultPackDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ShimejiPack", isDirectory: true)
    }

    private var manifestURL: URL {
        packDirectory.appendingPathComponent("manifest.json")
    }

    /// The parameters exist so tests can point an instance at a throwaway
    /// pack directory and defaults suite; the app only ever uses `shared`.
    init(packDirectory: URL? = nil, defaults: UserDefaults = .standard) {
        self.packDirectory = packDirectory ?? Self.defaultPackDirectory
        self.defaults = defaults
        super.init()
        loadFromDiskIfAvailable()
    }

    /// Survives relaunches so that removing the pack stays removed: without
    /// it, the settings screen's automatic download pulls it straight back
    /// down the next time the screen appears.
    private(set) var wasRemovedByUser: Bool {
        get { defaults.bool(forKey: Self.removedByUserKey) }
        set { defaults.set(newValue, forKey: Self.removedByUserKey) }
    }

    /// Called at app launch (and whenever the experiment toggle turns on) to
    /// pick up an already-downloaded pack without re-fetching it.
    func loadFromDiskIfAvailable() {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(ShimejiManifest.self, from: data)
            state = .ready
            // A pack that is back on disk makes the removal flag stale.
            wasRemovedByUser = false
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

    /// Automatic entry point (screen appearance, experiment toggle). Heals a
    /// missing pack, but leaves an explicitly removed one alone.
    func downloadIfNeeded() {
        guard !wasRemovedByUser else { return }
        startDownload()
    }

    /// Explicit user request, which also clears an earlier removal.
    func download() {
        wasRemovedByUser = false
        startDownload()
    }

    private func startDownload() {
        guard case .notDownloaded = state else { return }
        state = .downloading(progress: 0)
        let generation = operationGeneration

        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: ShimejiResourceManager.packURL) { [weak self] tempURL, _, error in
            Self.deliverDownloadCompletion(
                to: self,
                tempURL: tempURL,
                error: error,
                generation: generation
            )
        }
        progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Self.deliverProgress(progress.fractionCompleted, to: self, generation: generation)
        }
        downloadTask = task
        task.resume()
    }

    func retry() {
        invalidateCurrentOperation()
        state = .notDownloaded
        download()
    }

    private func handleDownloadCompletion(tempURL: URL?, error: Error?, generation: UInt) {
        guard generation == operationGeneration else { return }
        progressObservation = nil
        downloadTask = nil

        guard let tempURL else {
            state = .failed(error?.localizedDescription ?? "Download failed.")
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

        installationTask = Task { @MainActor [weak self] in
            defer {
                try? FileManager.default.removeItem(at: stagedZip)
            }

            do {
                let preparedPack = try await Task.detached(priority: .userInitiated) {
                    try Self.extractPack(zipURL: stagedZip)
                }.value

                guard let self else {
                    Self.discardPreparedPack(preparedPack)
                    return
                }
                guard !Task.isCancelled, generation == self.operationGeneration else {
                    Self.discardPreparedPack(preparedPack)
                    return
                }

                // This synchronous swap runs on the main actor so delete/retry
                // cannot invalidate the generation between the check and move.
                try Self.installPreparedPack(preparedPack, at: self.packDirectory)

                guard !Task.isCancelled, generation == self.operationGeneration else {
                    return
                }
                self.manifest = preparedPack.manifest
                self.state = .ready
                self.installationTask = nil
            } catch {
                guard let self,
                      !Task.isCancelled,
                      generation == self.operationGeneration
                else { return }
                self.installationTask = nil
                self.state = .failed("Couldn't set up the pack: \(error.localizedDescription)")
            }
        }
    }

    private nonisolated static func deliverDownloadCompletion(
        to manager: ShimejiResourceManager?,
        tempURL: URL?,
        error: Error?,
        generation: UInt
    ) {
        Task { @MainActor in
            manager?.handleDownloadCompletion(
                tempURL: tempURL,
                error: error,
                generation: generation
            )
        }
    }

    private nonisolated static func deliverProgress(
        _ progress: Double,
        to manager: ShimejiResourceManager?,
        generation: UInt
    ) {
        Task { @MainActor in
            guard let manager,
                  generation == manager.operationGeneration,
                  case .downloading = manager.state
            else { return }
            manager.state = .downloading(progress: progress)
        }
    }

    private nonisolated struct PreparedPack: Sendable {
        let manifest: ShimejiManifest
        let stagingDirectory: URL
    }

    private nonisolated static func extractPack(zipURL: URL) throws -> PreparedPack {
        let fm = FileManager.default

        // Extraction only touches a unique temporary location. The actor-
        // isolated caller decides whether this generation may install it.
        let stagingDirectory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
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
            return PreparedPack(manifest: manifest, stagingDirectory: stagingDirectory)
        } catch {
            try? fm.removeItem(at: stagingDirectory)
            throw error
        }
    }

    private nonisolated static func installPreparedPack(_ preparedPack: PreparedPack, at packDirectory: URL) throws {
        let fm = FileManager.default
        let base = packDirectory.deletingLastPathComponent()
        // Application Support isn't guaranteed to exist on disk yet on a
        // fresh install — FileManager just hands back the URL it *would*
        // use, without creating it. Moving into a directory whose parent
        // doesn't exist fails, so make sure it's really there first.
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        if fm.fileExists(atPath: packDirectory.path) {
            try fm.removeItem(at: packDirectory)
        }
        try fm.moveItem(at: preparedPack.stagingDirectory, to: packDirectory)
    }

    private nonisolated static func discardPreparedPack(_ preparedPack: PreparedPack) {
        try? FileManager.default.removeItem(at: preparedPack.stagingDirectory)
    }

    private func invalidateCurrentOperation() {
        operationGeneration &+= 1
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation = nil
        installationTask?.cancel()
        installationTask = nil
    }

    func deleteDownloadedPack() {
        invalidateCurrentOperation()
        try? FileManager.default.removeItem(at: packDirectory)
        manifest = nil
        state = .notDownloaded
        wasRemovedByUser = true
    }
}
