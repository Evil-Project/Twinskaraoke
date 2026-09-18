import Foundation

/// URLSession owns transfers across suspension and system termination. The
/// delegate takes ownership of temporary files before returning to Foundation.
nonisolated final class BackgroundDownloadTransport: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "Twinskaraoke.offline-downloads.v1"
    private let lock = NSLock()
    private var staged: [Int: URL] = [:]
    private var stagingErrors: [Int: Error] = [:]
    private var deliveries: [Int: URLSessionTask] = [:]
    private var pendingDeliveries = 0
    private var eventsFinished = false
    private var eventCompletion: (@Sendable () -> Void)?

    static var inboxDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DownloadInbox", isDirectory: true)
    }

    static func receipts() throws -> [DownloadReceipt] {
        do {
            return try FileManager.default.contentsOfDirectory(at: inboxDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { try JSONDecoder().decode(DownloadReceipt.self, from: Data(contentsOf: $0)) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    static func discardReceipt(for file: URL) {
        try? FileManager.default.removeItem(at: file.appendingPathExtension("json"))
        try? FileManager.default.removeItem(at: file)
    }

    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func handleEvents(completion: @escaping @Sendable () -> Void) {
        lock.lock()
        eventCompletion = completion
        lock.unlock()
        finishEventsIfReady()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let directory = Self.inboxDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: destination)
            let receipt = DownloadReceipt(
                token: downloadTask.taskDescription ?? "",
                filename: destination.lastPathComponent,
                responseURL: downloadTask.response?.url,
                status: (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0,
                headers: (downloadTask.response as? HTTPURLResponse)?.allHeaderFields.reduce(into: [String: String]()) {
                    $0[String(describing: $1.key)] = String(describing: $1.value)
                } ?? [:]
            )
            try JSONEncoder().encode(receipt).write(to: destination.appendingPathExtension("json"), options: .atomic)
            lock.lock()
            staged[downloadTask.taskIdentifier] = destination
            lock.unlock()
        } catch {
            lock.lock()
            stagingErrors[downloadTask.taskIdentifier] = error
            lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let url = staged.removeValue(forKey: task.taskIdentifier)
        let stagingError = stagingErrors.removeValue(forKey: task.taskIdentifier)
        let failure = error ?? stagingError
        deliveries[task.taskIdentifier] = task
        pendingDeliveries += 1
        lock.unlock()
        Task {
            await DownloadManager.shared.receiveBackgroundDownload(task: task, file: url, error: failure)
            deliveryFinished(taskID: task.taskIdentifier)
        }
    }

    func completingTasks() -> [URLSessionTask] {
        lock.lock()
        defer { lock.unlock() }
        return Array(deliveries.values)
    }

    private func deliveryFinished(taskID: Int) {
        lock.lock()
        deliveries.removeValue(forKey: taskID)
        pendingDeliveries -= 1
        lock.unlock()
        finishEventsIfReady()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        eventsFinished = true
        lock.unlock()
        finishEventsIfReady()
    }

    private func finishEventsIfReady() {
        lock.lock()
        let completion = eventsFinished && pendingDeliveries == 0 ? eventCompletion : nil
        if eventsFinished && pendingDeliveries == 0 {
            // A foreground delivery may have no app-delegate completion.
            // Consume that batch too; it cannot satisfy a later wake event.
            eventCompletion = nil
            eventsFinished = false
        }
        lock.unlock()
        if let completion { DispatchQueue.main.async(execute: completion) }
    }
}

nonisolated struct PendingDownload: Codable, Sendable {
    let song: Song
    let token: UUID
}

nonisolated struct DownloadReceipt: Codable, Sendable {
    let token: String
    let filename: String
    let responseURL: URL?
    let status: Int
    let headers: [String: String]

    var file: URL { BackgroundDownloadTransport.inboxDirectory.appendingPathComponent(filename) }
    var response: HTTPURLResponse? {
        guard let responseURL else { return nil }
        return HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: nil, headerFields: headers)
    }
}
