import AVFoundation
import Foundation
import Observation
import WatchKit

/// Explicit downloads live in Application Support, outside the evictable
/// playback cache. The manifest preserves song metadata for offline browsing.
@MainActor
@Observable
final class WatchDownloads: NSObject {
    static let shared = WatchDownloads()
    nonisolated static let sessionIdentifier = "org.twinskaraoke.watch.downloads.v1"
    nonisolated static let storageLimit: Int64 = 512 * 1024 * 1024

    nonisolated enum Status: String, Codable, Sendable { case waiting, downloading, ready, failed }
    nonisolated struct Entry: Codable, Identifiable, Sendable {
        var song: Song
        var transferID = UUID()
        var status: Status = .waiting
        var progress: Double = 0
        var error: String?
        var fileExtension: String?
        var id: String { song.id }
    }

    private(set) var entries: [Entry] = []
    private(set) var storageRevision = 0
    private(set) var error: String?
    @ObservationIgnored private var backgroundTasks: [WKURLSessionRefreshBackgroundTask] = []
    @ObservationIgnored private var finishedEvents = false
    @ObservationIgnored private var validations = 0
    @ObservationIgnored private var resolutionTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let loadSong: @Sendable (String) async throws -> Song
    @ObservationIgnored private var pendingCompletions: Set<String> = []
    nonisolated let storageDirectory: URL
    @ObservationIgnored private let sessionConfiguration: URLSessionConfiguration?
    @ObservationIgnored private lazy var session: URLSession = {
        let configuration = sessionConfiguration ?? URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    nonisolated static let directory: URL = {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()
    private var manifestURL: URL { storageDirectory.appendingPathComponent("manifest.json") }
    func fileURL(for id: String) -> URL {
        let suffix = entry(for: id)?.fileExtension ?? "mp3"
        return storageDirectory.appendingPathComponent(SongStorageKey.component(for: id) + "." + suffix)
    }

    init(directory: URL = WatchDownloads.directory, sessionConfiguration: URLSessionConfiguration? = nil,
         loadSong: @escaping @Sendable (String) async throws -> Song = { try await KaraokeAPIClient.fetchSong(id: $0) }) {
        self.sessionConfiguration = sessionConfiguration
        self.loadSong = loadSong
        storageDirectory = directory
        super.init()
        if let data = try? Data(contentsOf: manifestURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved.map { entry in
                var entry = entry
                if entry.fileExtension == nil {
                    let legacy = directory.appendingPathComponent(SongStorageKey.component(for: entry.id) + ".audio")
                    let migrated = directory.appendingPathComponent(SongStorageKey.component(for: entry.id) + ".mp3")
                    if FileManager.default.fileExists(atPath: legacy.path), !FileManager.default.fileExists(atPath: migrated.path) {
                        try? FileManager.default.moveItem(at: legacy, to: migrated)
                    }
                    entry.fileExtension = "mp3"
                }
                let savedURL = directory.appendingPathComponent(SongStorageKey.component(for: entry.id) + "." + (entry.fileExtension ?? "mp3"))
                if entry.status == .ready, !FileManager.default.fileExists(atPath: savedURL.path) {
                    entry.status = .failed
                    entry.error = "Download is missing. Download it again."
                }
                return entry
            }
            persist()
        }
    }

    func activate() {
        let pending = Set(entries.filter { $0.status == .waiting || $0.status == .downloading }.map(\.transferID))
        let session = session
        Task {
            let tasks = await session.allTasks
            let running = Set(tasks.compactMap { $0.taskDescription }.compactMap(UUID.init(uuidString:)))
            reconcileInterruptedTransfers(pending: pending, running: running)
            let known = Set(entries.map { $0.transferID.uuidString })
            for task in tasks where !known.contains(task.taskDescription ?? "") { task.cancel() }
            persist()
        }
    }

    /// Re-check live status after task inventory suspends: delegate callbacks
    /// may have completed or started validation since `pending` was captured.
    func reconcileInterruptedTransfers(pending: Set<UUID>, running: Set<UUID>) {
        for index in entries.indices where pending.contains(entries[index].transferID)
            && !running.contains(entries[index].transferID)
            && (entries[index].status == .waiting || entries[index].status == .downloading)
            && !pendingCompletions.contains(entries[index].transferID.uuidString) {
            entries[index].status = .failed
            entries[index].error = "Download was interrupted. Tap Retry."
        }
    }

    var songs: [Song] { entries.filter { $0.status == .ready }.map(\.song) }
    var sizeBytes: Int64 { songs.reduce(0) { $0 + Self.fileSize(fileURL(for: $1.id)) } }
    /// Includes orphaned audio and staging files that still occupy storage.
    var storageBytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: storageDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])) ?? []
        return files.reduce(0) { total, file in
            guard file.lastPathComponent != "manifest.json",
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return total }
            return total + Self.fileSize(file)
        }
    }
    func entry(for id: String) -> Entry? { entries.first { $0.id == id } }
    func localURL(for id: String) -> URL? {
        guard entry(for: id)?.status == .ready else { return nil }
        let url = fileURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func download(_ song: Song) {
        guard entry(for: song.id)?.status != .ready,
              entry(for: song.id)?.status != .downloading,
              entry(for: song.id)?.status != .waiting else { return }
        guard sizeBytes < Self.storageLimit else {
            error = "Watch downloads are full (512 MB). Remove a download and try again."
            return
        }
        entries.removeAll { $0.id == song.id }
        let entry = Entry(song: song)
        entries.append(entry)
        persist()
        if let url = song.audioURL {
            startTransfer(entry: entry, url: url)
        } else {
            let loader = loadSong
            resolutionTasks[song.id] = Task { [weak self] in
                defer {
                    if self?.entry(for: song.id)?.transferID == entry.transferID {
                        self?.resolutionTasks[song.id] = nil
                    }
                }
                do {
                    let canonical = try await loader(song.id)
                    try Task.checkCancellation()
                    guard let self, let index = self.entries.firstIndex(where: { $0.transferID == entry.transferID }) else { return }
                    let resolved = song.fillingMissingMetadata(from: canonical)
                    guard let url = resolved.audioURL else {
                        self.fail(entry.transferID.uuidString, message: "This song has no downloadable audio. Choose another song.")
                        return
                    }
                    self.entries[index].song = resolved
                    self.persist()
                    self.startTransfer(entry: self.entries[index], url: url)
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.fail(entry.transferID.uuidString, message: "Couldn't load this song's audio. Sync your iPhone account and tap Retry.")
                }
            }
        }
    }

    private func startTransfer(entry: Entry, url: URL) {
        guard ["https", "http"].contains(url.scheme ?? "") else {
            fail(entry.transferID.uuidString, message: "This song has no downloadable audio.")
            return
        }
        let task = session.downloadTask(with: url)
        task.taskDescription = entry.transferID.uuidString
        task.resume()
    }

    func remove(_ id: String) {
        guard let entry = entry(for: id) else { return }
        let savedURL = fileURL(for: id)
        resolutionTasks.removeValue(forKey: id)?.cancel()
        entries.removeAll { $0.id == id }
        persist()
        try? FileManager.default.removeItem(at: savedURL)
        guard entry.status == .waiting || entry.status == .downloading else { return }
        let session = session
        Task {
            for task in await session.allTasks where task.taskDescription == entry.transferID.uuidString { task.cancel() }
        }
    }

    func removeAll() {
        resolutionTasks.values.forEach { $0.cancel() }
        resolutionTasks.removeAll()
        for id in entries.map(\.id) { remove(id) }
    }

    func clearStorage() {
        removeAll()
        error = nil
        let files = (try? FileManager.default.contentsOfDirectory(at: storageDirectory,
            includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != "manifest.json" {
            do { try FileManager.default.removeItem(at: file) }
            catch { self.error = "Some watch audio couldn't be removed. Try clearing again." }
        }
        persist()
        // Cancel restored transfers with no live manifest entry, too.
        let session = session
        Task {
            let tasks = await session.allTasks
            let live = Set(entries.map { $0.transferID.uuidString })
            for task in tasks where !live.contains(task.taskDescription ?? "") { task.cancel() }
        }
    }

    func invalidate(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .failed
        entries[index].error = "The downloaded audio is damaged. Download it again."
        try? FileManager.default.removeItem(at: fileURL(for: id))
        persist()
    }

    func dismissError() { error = nil }

    private func persist() {
        storageRevision &+= 1
        do { try JSONEncoder().encode(entries).write(to: manifestURL, options: .atomic) }
        catch { self.error = "Couldn't save watch downloads. Free some space and try again." }
    }

    private nonisolated static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    func complete(transferID: String, stagedURL: URL?) async {
        validations += 1
        defer {
            validations -= 1
            pendingCompletions.remove(transferID)
            if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
            finishBackgroundTasksIfReady()
        }
        guard let index = entries.firstIndex(where: { $0.transferID.uuidString == transferID }) else { return }
        let entry = entries[index]
        guard let stagedURL else {
            fail(transferID, message: "Couldn't download playable audio. Sync your account, check the connection, and tap Retry.")
            return
        }
        do {
            let asset = AVURLAsset(url: stagedURL)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            guard playable, duration.isFinite, duration > 0,
                  entry.song.duration <= 0 || duration >= Double(entry.song.duration) * 0.8 else {
                fail(transferID, message: "Downloaded audio is incomplete. Tap Retry.")
                return
            }
            guard let current = entries.firstIndex(where: { $0.transferID.uuidString == transferID }) else { return }
            guard sizeBytes + Self.fileSize(stagedURL) <= Self.storageLimit else {
                fail(transferID, message: "Watch downloads are full (512 MB). Remove a download and retry.")
                return
            }
            let suffix = Self.audioExtension(mimeType: nil, url: stagedURL)
            entries[current].fileExtension = suffix
            let destination = fileURL(for: entry.id)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: stagedURL, to: destination)
            entries[current].status = .ready
            entries[current].progress = 1
            entries[current].error = nil
            persist()
        } catch {
            fail(transferID, message: "Couldn't save playable audio. Free some space or retry.")
        }
    }

    private func fail(_ transferID: String, message: String) {
        guard let index = entries.firstIndex(where: { $0.transferID.uuidString == transferID }) else { return }
        entries[index].status = .failed
        entries[index].error = message
        persist()
    }

    nonisolated static func audioExtension(mimeType: String?, url: URL?) -> String {
        let known: Set<String> = ["mp3", "m4a", "mp4", "aac", "wav", "aif", "aiff", "caf", "flac"]
        if let suffix = url?.pathExtension.lowercased(), known.contains(suffix) { return suffix }
        switch mimeType?.lowercased() {
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/mp4", "video/mp4", "audio/x-m4a": return "m4a"
        case "audio/aac", "audio/aacp": return "aac"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        case "audio/x-caf": return "caf"
        default: return "mp3"
        }
    }

    nonisolated static func responseError(_ response: URLResponse?) -> String? {
        guard let response = response as? HTTPURLResponse else { return nil }
        switch response.statusCode {
        case 200 ... 299: return nil
        case 401, 403: return "Audio access was denied. Open iPhone to sync your account, then tap Retry."
        case 404: return "This song's audio is unavailable on the server. Choose another song."
        default: return "The audio server returned error \(response.statusCode). Tap Retry."
        }
    }

    nonisolated static func transferError(_ error: Error?) -> String {
        if let error = error as? URLError, error.code == .notConnectedToInternet {
            return "Watch is offline. Connect to Wi-Fi or your iPhone and tap Retry."
        }
        return "Download stopped. Check your connection and tap Retry."
    }

    func handle(_ task: WKURLSessionRefreshBackgroundTask) {
        backgroundTasks.append(task)
        _ = session
        finishBackgroundTasksIfReady()
    }

    private func finishBackgroundTasksIfReady() {
        guard finishedEvents, validations == 0, pendingCompletions.isEmpty, !backgroundTasks.isEmpty else { return }
        for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
        backgroundTasks = []
        finishedEvents = false
    }
}

extension WatchDownloads: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskDescription ?? ""
        let suffix = Self.audioExtension(mimeType: downloadTask.response?.mimeType, url: downloadTask.response?.url)
        let staged = storageDirectory.appendingPathComponent("staging-" + UUID().uuidString + "." + suffix)
        // URLSession deletes its temporary file when this delegate returns.
        let responseError = Self.responseError(downloadTask.response)
        let stored = responseError == nil && AudioManager.acceptsAudioResponse(downloadTask.response)
            && AudioManager.storeDownloadedAudio(tempURL: location, destinationURL: staged)
        // This delegate uses OperationQueue.main. Register synchronously so
        // didFinishEvents cannot finish the watch task before validation starts.
        MainActor.assumeIsolated { _ = pendingCompletions.insert(id) }
        Task { @MainActor [weak self] in
            if let responseError { self?.fail(id, message: responseError) }
            await self?.complete(transferID: id, stagedURL: stored ? staged : nil)
            if let responseError { self?.fail(id, message: responseError) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                               totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskDescription ?? ""
        Task { @MainActor [weak self] in
            guard let self, let index = self.entries.firstIndex(where: { $0.transferID.uuidString == id }) else { return }
            guard self.entries[index].status == .waiting || self.entries[index].status == .downloading else { return }
            self.entries[index].status = .downloading
            self.entries[index].progress = totalBytesExpectedToWrite > 0
                ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : 0
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil else { return }
        let id = task.taskDescription ?? ""
        Task { @MainActor [weak self] in self?.fail(id, message: Self.transferError(error)) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            self?.finishedEvents = true
            self?.finishBackgroundTasksIfReady()
        }
    }
}

final class WatchDownloadAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let downloadTask = task as? WKURLSessionRefreshBackgroundTask {
                WatchDownloads.shared.handle(downloadTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
