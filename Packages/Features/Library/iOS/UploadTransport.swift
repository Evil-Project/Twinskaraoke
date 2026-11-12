import Foundation
import Synchronization

/// Sends staged upload bodies. The live transport uses a background
/// `URLSession`, so a transfer keeps going while the app is suspended or
/// after the system ends it; tests use a stub.
nonisolated struct UploadTransport: Sendable {
    enum Failure: Sendable, Equatable {
        case cancelled
        case urlError(URLError.Code)
    }

    enum Event: Sendable, Equatable {
        case progress(taskID: Int, fraction: Double)
        /// The server answered; `status` may be any HTTP status.
        case finished(taskID: Int, status: Int, body: Data, contentType: String?, retryAfter: TimeInterval?)
        /// No answer arrived.
        case failed(taskID: Int, Failure)

        var taskID: Int {
            switch self {
            case let .progress(taskID, _), let .finished(taskID, _, _, _, _), let .failed(taskID, _): taskID
            }
        }
    }

    /// Starts sending `stagedFile` with `request` and returns the task id.
    var start: @Sendable (_ request: URLRequest, _ stagedFile: URL) async throws -> Int
    var cancel: @Sendable (_ taskID: Int) async -> Void
    /// Tasks the session is still running, including ones it carried over
    /// from an earlier launch.
    var activeTaskIDs: @Sendable () async -> Set<Int>
    /// Every event, in order. One consumer; events before it subscribes are
    /// kept until it does.
    var events: @Sendable () -> AsyncStream<Event>
    /// Called by the consumer once it has handled (and stored) a finished
    /// or failed event, so a background wake isn't ended before that.
    var acknowledge: @Sendable (_ taskID: Int) -> Void
    /// Returns once the session has delivered everything the system woke or
    /// relaunched the app for, and each was acknowledged.
    var handleBackgroundEvents: @Sendable () async -> Void

    static let sessionIdentifier = "Twinskaraoke.song-uploads.v1"

    /// The background session, created the first time anything here is used:
    /// the first upload, or the system relaunching the app for the session.
    static var live: UploadTransport {
        UploadTransport(
            start: { request, file in BackgroundUploadSession.shared.start(request, from: file) },
            cancel: { taskID in await BackgroundUploadSession.shared.cancel(taskID) },
            activeTaskIDs: { await BackgroundUploadSession.shared.activeTaskIDs() },
            events: { BackgroundUploadSession.shared.delegate.events },
            acknowledge: { taskID in BackgroundUploadSession.shared.delegate.acknowledge(taskID) },
            handleBackgroundEvents: {
                await withCheckedContinuation { continuation in
                    BackgroundUploadSession.shared.delegate.handleEvents { continuation.resume() }
                }
            }
        )
    }
}

/// Owns the one background session for uploads. Creating it reconnects to
/// the transfers an earlier process started.
nonisolated final class BackgroundUploadSession: Sendable {
    static let shared = BackgroundUploadSession()

    let delegate = UploadSessionDelegate()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.background(withIdentifier: UploadTransport.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
    }

    /// `uploadTask(with:fromFile:)`: a background session can only send a
    /// body from a file, and its async upload methods aren't supported.
    func start(_ request: URLRequest, from file: URL) -> Int {
        let task = session.uploadTask(with: request, fromFile: file)
        task.resume()
        return task.taskIdentifier
    }

    func cancel(_ taskID: Int) async {
        await session.allTasks.first { $0.taskIdentifier == taskID }?.cancel()
    }

    func activeTaskIDs() async -> Set<Int> {
        let tasks = await session.allTasks
        return Set(tasks.filter { $0.state == .running || $0.state == .suspended }.map(\.taskIdentifier))
    }
}

/// Collects each task's response body and turns the session's callbacks
/// into `UploadTransport.Event`s.
///
/// Concurrency: the session calls this on its serial delegate queue, and the
/// app reads it from other tasks. Every mutable field sits in one `Mutex`,
/// and the stream continuation is itself `Sendable`, so the class is
/// `Sendable` without any unchecked conformance.
nonisolated final class UploadSessionDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var bodies: [Int: Data] = [:]
        /// Finished or failed events the consumer hasn't acknowledged yet.
        var unacknowledged: Set<Int> = []
        var eventsFinished = false
        var completion: (@Sendable () -> Void)?
    }

    /// An error page is all a body can be here, so it is cut off early.
    private static let maxBodyBytes = 64 * 1024

    let events: AsyncStream<UploadTransport.Event>
    private let continuation: AsyncStream<UploadTransport.Event>.Continuation
    private let state = Mutex(State())

    override init() {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        continuation.yield(.progress(taskID: task.taskIdentifier, fraction: fraction))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        state.withLock { state in
            var body = state.bodies[dataTask.taskIdentifier] ?? Data()
            guard body.count < Self.maxBodyBytes else { return }
            body.append(data.prefix(Self.maxBodyBytes - body.count))
            state.bodies[dataTask.taskIdentifier] = body
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        let body = state.withLock { state in
            state.unacknowledged.insert(taskID)
            return state.bodies.removeValue(forKey: taskID) ?? Data()
        }
        if let error {
            let code = (error as? URLError)?.code ?? .unknown
            continuation.yield(.failed(taskID: taskID, code == .cancelled ? .cancelled : .urlError(code)))
        } else if let response = task.response as? HTTPURLResponse {
            continuation.yield(.finished(
                taskID: taskID,
                status: response.statusCode,
                body: body,
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                retryAfter: KaraokeAPIClient.retryAfterSeconds(response.value(forHTTPHeaderField: "Retry-After"))
            ))
        } else {
            continuation.yield(.failed(taskID: taskID, .urlError(.badServerResponse)))
        }
    }

    func acknowledge(_ taskID: Int) {
        _ = state.withLock { $0.unacknowledged.remove(taskID) }
        finishEventsIfReady()
    }

    /// Sent only when the system woke or relaunched the app for the
    /// session, after the last event of that wake.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        state.withLock { $0.eventsFinished = true }
        finishEventsIfReady()
    }

    /// SwiftUI hands over the wake's completion after the session exists, so
    /// its events may already have finished; the flag covers that order.
    func handleEvents(completion: @escaping @Sendable () -> Void) {
        state.withLock { $0.completion = completion }
        finishEventsIfReady()
    }

    private func finishEventsIfReady() {
        let completion = state.withLock { state -> (@Sendable () -> Void)? in
            guard state.eventsFinished, state.unacknowledged.isEmpty, let completion = state.completion else {
                return nil
            }
            state.eventsFinished = false
            state.completion = nil
            return completion
        }
        if let completion { DispatchQueue.main.async(execute: completion) }
    }
}
