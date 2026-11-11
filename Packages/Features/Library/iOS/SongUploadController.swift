import Foundation
import Observation

/// Adds songs to the user's uploads, from files or links, one at a time.
///
/// A file's body is staged to disk and sent by the background upload
/// session, so it keeps going while the app is suspended; the outbox
/// remembers it across relaunches. A link import is one long foreground
/// request. Nothing is retried without the user asking: an upload is a POST,
/// and a repeat could add the song twice.
///
/// Created on first use. Nothing touches it at launch except the background
/// session's relaunch hook, and the session itself is only created once an
/// upload needs it.
@MainActor
@Observable
final class SongUploadController {
    typealias Item = SongUploadItem
    typealias Completion = SongUploadCompletion

    static let shared = SongUploadController()

    private(set) var uploads: [Item] = []
    /// Bumped after every successful upload; the Uploaded list refreshes on it.
    private(set) var completedUploads = 0
    /// The last upload that ended, until `acknowledgeCompletion()`.
    private(set) var latestCompletion: Completion?

    /// What the controller keeps per upload beyond what the UI shows.
    struct Record {
        enum Source {
            case file(URL, SongUploadMetadata)
            case link(URL, playlistID: String?)
        }

        /// `nil` for an upload restored from the outbox, which only has its
        /// staged body.
        var source: Source?
        /// Identifies the same file or link, to ignore a second start.
        var key: String
        var staged: StagedUpload?
        var taskID: Int?
        var knownSongIDs: Set<String>?
        /// A finished or failed event is being handled.
        var settling = false
        /// The account that started the upload; `nil` when it couldn't be
        /// told. It is never sent, imported or retried for another one.
        var account: String?
        /// Started by an account that has since signed out: the upload is
        /// dropped from the list when it ends.
        var leavesListWhenEnded = false
    }

    @ObservationIgnored let service: Service
    @ObservationIgnored let vanishedGrace: Duration
    @ObservationIgnored var records: [UUID: Record] = [:]
    @ObservationIgnored private var work: (itemID: UUID, task: Task<Void, Never>)?
    @ObservationIgnored private var eventLoop: Task<Void, Never>?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var hasResumed = false
    @ObservationIgnored private var isStartingTransfer = false
    /// Events for tasks no upload claims yet: during a relaunch, or while a
    /// task's id is on its way back from `start`.
    @ObservationIgnored private var unclaimedEvents: [Int: [UploadTransport.Event]] = [:]
    @ObservationIgnored private var cancelledTaskIDs: Set<Int> = []
    @ObservationIgnored private var sessionObserver: NSObjectProtocol?

    /// `vanishedGrace` is how long a restored upload whose task is gone may
    /// wait for the session's event before the server is asked instead.
    init(
        service: Service = AppRuntime.isUITestMode ? .uiTestFixture : .live,
        vanishedGrace: Duration = .seconds(3)
    ) {
        self.service = service
        self.vanishedGrace = vanishedGrace
        sessionObserver = NotificationCenter.default.addObserver(
            forName: WatchSessionLink.sessionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.accountMayHaveChanged() }
        }
        Task { [weak self] in await self?.resume() }
    }

    isolated deinit {
        work?.task.cancel()
        eventLoop?.cancel()
        resumeTask?.cancel()
        if let sessionObserver { NotificationCenter.default.removeObserver(sessionObserver) }
    }

    // MARK: - Starting

    /// Queues `source` for upload and returns its item id, or `nil` when the
    /// same file is already on its way. A blank title becomes the file name.
    @discardableResult
    func uploadFile(at source: URL, metadata: SongUploadMetadata) -> UUID? {
        let key = "file:" + source.standardizedFileURL.path
        guard !isActive(key: key) else { return nil }
        var metadata = metadata
        if metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let title = SongUploadMetadata.defaultTitle(forFilename: source.lastPathComponent)
        {
            metadata.title = title
        }
        return enqueue(.file, title: metadata.title, record: Record(source: .file(source, metadata), key: key))
    }

    /// Queues a link import and returns its item id, or `nil` when the same
    /// link is already on its way. A link the server can't import fails at
    /// once, without a request.
    @discardableResult
    func importLink(_ text: String, playlistID: String? = nil) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let link = SongLinkImport.supportedLink(trimmed) else {
            let id = UUID()
            records[id] = Record(source: nil, key: "", account: service.currentAccount())
            let problem = SongLinkImport.problem(with: trimmed) ?? .unsupportedSite
            uploads.append(Item(id: id, title: trimmed, kind: .link, phase: .failed(.unsupportedLink(problem))))
            return id
        }
        let key = "link:" + link.absoluteString
        guard !isActive(key: key) else { return nil }
        let record = Record(source: .link(link, playlistID: playlistID), key: key)
        return enqueue(.link, title: link.absoluteString, record: record)
    }

    private func enqueue(_ kind: Item.Kind, title: String, record: Record) -> UUID {
        let id = UUID()
        var record = record
        record.account = service.currentAccount()
        records[id] = record
        uploads.append(Item(id: id, title: title, kind: kind, phase: .waiting))
        startNext()
        return id
    }

    private func isActive(key: String) -> Bool {
        uploads.contains { $0.isActive && records[$0.id]?.key == key }
    }

    /// Starts the first waiting upload unless one is already running.
    private func startNext() {
        guard hasResumed else {
            Task { [weak self] in
                await self?.resume()
                self?.startNext()
            }
            return
        }
        guard !uploads.contains(where: { $0.isActive && $0.phase != .waiting }),
              let next = uploads.first(where: { $0.phase == .waiting })
        else { return }
        setPhase(next.id, next.kind == .link ? .importing : .checkingQuota)
        work = (next.id, Task { [weak self] in await self?.run(next.id) })
    }

    private func run(_ id: UUID) async {
        guard !refuseForAnotherAccount(id) else { return }
        switch records[id]?.source {
        case let .file(source, metadata):
            await runFile(id, source: source, metadata: metadata)
        case let .link(link, playlistID):
            await runLink(id, link: link, playlistID: playlistID)
        case nil:
            if records[id]?.staged != nil { await send(id) }
        }
    }

    private func isCurrent(_ id: UUID) -> Bool {
        !Task.isCancelled && records[id] != nil
    }

    // MARK: - File uploads

    private func runFile(_ id: UUID, source: URL, metadata: SongUploadMetadata) async {
        guard records[id]?.staged == nil else { return await send(id) }
        setPhase(id, .checkingQuota)
        // Limits that can't be loaded don't block: the server decides.
        if let size = service.fileSize(source),
           let limits = try? await service.limits(),
           let blocked = limits.blocking(fileSize: size)
        {
            return fail(id, blocked)
        }
        guard isCurrent(id) else { return }
        records[id]?.knownSongIDs = try? await service.uploadedSongIDs()
        guard isCurrent(id) else { return }
        setPhase(id, .preparing)
        let staged: StagedUpload
        do {
            staged = try await service.stage(source, metadata)
        } catch {
            guard isCurrent(id) else { return }
            return fail(id, error as? SongUploadFailure ?? .fileUnreadable)
        }
        guard isCurrent(id) else { return service.discard(staged) }
        records[id]?.staged = staged
        await send(id)
    }

    /// Hands the staged body to the transport with a fresh token.
    private func send(_ id: UUID) async {
        guard let staged = records[id]?.staged, !refuseForAnotherAccount(id) else { return }
        let request: URLRequest
        do {
            request = try service.makeUploadRequest(staged)
        } catch {
            return fail(id, error as? SongUploadFailure ?? .unknown)
        }
        startEventLoop()
        setPhase(id, .uploading(0))
        isStartingTransfer = true
        let taskID: Int
        do {
            taskID = try await service.transport.start(request, staged.fileURL)
            isStartingTransfer = false
        } catch {
            isStartingTransfer = false
            dropUnclaimedEvents()
            return fail(id, .unknown)
        }
        guard records[id] != nil else {
            cancelledTaskIDs.insert(taskID)
            await service.transport.cancel(taskID)
            return dropUnclaimedEvents()
        }
        records[id]?.taskID = taskID
        service.outbox.save(PendingUpload(
            staged: staged,
            taskID: taskID,
            title: title(of: id),
            startedAt: Date(),
            knownSongIDs: records[id]?.knownSongIDs,
            account: records[id]?.account
        ))
        DebugLogger.log("Upload started: \(staged.bodyBytes) bytes", category: .network)
        replayUnclaimedEvents(for: taskID)
        dropUnclaimedEvents()
    }

    // MARK: - Link imports

    private func runLink(_ id: UUID, link: URL, playlistID: String?) async {
        setPhase(id, .importing)
        // An import that ends without an answer may still have landed; the
        // list from before tells.
        records[id]?.knownSongIDs = try? await service.uploadedSongIDs()
        guard isCurrent(id), !refuseForAnotherAccount(id) else { return }
        do {
            let result = try await service.importLink(SongLinkImport(url: link.absoluteString, playlistID: playlistID))
            guard records[id] != nil else { return }
            guard result?.success != false else { return fail(id, .server(status: 200, problem: nil)) }
            let serverTitle = result?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await succeed(id, title: serverTitle.isEmpty ? title(of: id) : serverTitle)
        } catch {
            guard records[id] != nil else { return }
            if let failure = error as? SongUploadFailure {
                if case let .server(401, problem) = failure {
                    let resolved = await unauthorizedFailure(problem)
                    return fail(id, resolved)
                }
                if Self.mayHaveLanded(failure) { return await settleAmbiguous(id, failure: failure) }
                return fail(id, failure)
            }
            // Cancelled without the user asking: the app was suspended or
            // the request was torn down. The user can try again unless the
            // import landed anyway.
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            guard cancelled else { return fail(id, .unknown) }
            await settleAmbiguous(id, failure: .interrupted)
        }
    }

    // MARK: - User actions

    /// Stops an upload that hasn't reached the server's answer yet and drops
    /// it from the list.
    func cancel(_ id: UUID) {
        guard let index = uploads.firstIndex(where: { $0.id == id }),
              uploads[index].isActive, uploads[index].phase != .finishing,
              let record = records.removeValue(forKey: id)
        else { return }
        uploads.remove(at: index)
        if work?.itemID == id {
            work?.task.cancel()
            work = nil
        }
        if let taskID = record.taskID {
            cancelledTaskIDs.insert(taskID)
            Task { await service.transport.cancel(taskID) }
        }
        if let staged = record.staged {
            service.discard(staged)
            service.outbox.remove(id: staged.id)
        }
        if case .link = record.source {
            // The server may finish the import anyway.
            Task { await service.invalidateUploads() }
        }
        DebugLogger.log("Upload cancelled", category: .network)
        startNext()
    }

    /// Queues a failed upload again. A staged body is sent as it is, with
    /// the current token.
    func retry(_ id: UUID) {
        guard let index = uploads.firstIndex(where: { $0.id == id }),
              case .failed = uploads[index].phase,
              let record = records[id], record.source != nil || record.staged != nil
        else { return }
        if let key = record.source.map({ _ in record.key }), isActive(key: key) { return }
        if belongsToAnotherAccount(id, current: service.currentAccount()) {
            uploads[index].phase = .failed(.signedOut)
            return
        }
        records[id]?.settling = false
        uploads[index].phase = .waiting
        startNext()
    }

    /// Removes an upload that has ended from the list.
    func dismiss(_ id: UUID) {
        guard let index = uploads.firstIndex(where: { $0.id == id }), !uploads[index].isActive else { return }
        uploads.remove(at: index)
        if let staged = records.removeValue(forKey: id)?.staged {
            service.discard(staged)
            service.outbox.remove(id: staged.id)
        }
    }

    func acknowledgeCompletion() {
        latestCompletion = nil
    }

    // MARK: - Relaunch

    /// Shows uploads an earlier launch left in the outbox and settles the
    /// ones that ended while the app was gone. Runs once; later calls wait
    /// for the first.
    func resume() async {
        if resumeTask == nil {
            resumeTask = Task { [weak self] in await self?.restore() }
        }
        await resumeTask?.value
    }

    /// For the background session's relaunch hook: returns once the session
    /// has delivered its events and each was handled.
    func handleBackgroundEvents() async {
        startEventLoop()
        await resume()
        await service.transport.handleBackgroundEvents()
    }

    private func restore() async {
        let entries = service.outbox.entries()
        service.sweepStaged(Set(entries.map(\.id)))
        guard !entries.isEmpty else {
            hasResumed = true
            // A background wake can bring events for tasks no entry names;
            // acknowledging them lets the wake end.
            dropUnclaimedEvents()
            return
        }
        startEventLoop()
        let active = await service.transport.activeTaskIDs()
        var vanished: [UUID] = []
        for entry in entries where records[entry.id] == nil {
            records[entry.id] = Record(
                source: nil,
                key: "staged:\(entry.id)",
                staged: entry.staged(),
                taskID: entry.taskID,
                knownSongIDs: entry.knownSongIDs,
                account: entry.account
            )
            let running = entry.taskID.map(active.contains) ?? false
            uploads.append(Item(id: entry.id, title: entry.title, kind: .file, phase: running ? .uploading(0) : .finishing))
            if let taskID = entry.taskID { replayUnclaimedEvents(for: taskID) }
            if !running { vanished.append(entry.id) }
        }
        hasResumed = true
        dropUnclaimedEvents()
        DebugLogger.log("Upload outbox restored: \(entries.count) pending, \(active.count) running", category: .network)
        for id in vanished {
            Task { [weak self] in await self?.settleVanished(id) }
        }
    }

    /// A restored upload whose task is gone and sent no event in time: the
    /// server's list tells whether it arrived.
    private func settleVanished(_ id: UUID) async {
        try? await Task.sleep(for: vanishedGrace)
        guard let record = records[id], !record.settling, item(id)?.isActive == true else { return }
        records[id]?.settling = true
        await settleAmbiguous(id, failure: .interrupted)
    }

    // MARK: - Events

    private func startEventLoop() {
        guard eventLoop == nil else { return }
        let events = service.transport.events()
        eventLoop = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                handle(event)
            }
        }
    }

    private func handle(_ event: UploadTransport.Event) {
        let taskID = event.taskID
        if cancelledTaskIDs.contains(taskID) {
            if case .progress = event { return }
            cancelledTaskIDs.remove(taskID)
            return service.transport.acknowledge(taskID)
        }
        guard let id = records.first(where: { $0.value.taskID == taskID })?.key else {
            guard !hasResumed || isStartingTransfer else {
                if case .progress = event { return }
                return service.transport.acknowledge(taskID)
            }
            unclaimedEvents[taskID, default: []].append(event)
            return
        }
        switch event {
        case let .progress(_, fraction):
            guard item(id)?.isActive == true, records[id]?.settling == false else { return }
            setPhase(id, fraction >= 1 ? .finishing : .uploading(fraction))
        case let .finished(_, status, body, contentType, retryAfter):
            records[id]?.settling = true
            // From here the server has answered: cancel must not remove it.
            if item(id)?.isActive == true { setPhase(id, .finishing) }
            Task { [weak self] in
                await self?.settleAnswer(id, status: status, body: body, contentType: contentType, retryAfter: retryAfter)
                self?.service.transport.acknowledge(taskID)
            }
        case let .failed(_, failure):
            records[id]?.settling = true
            if item(id)?.isActive == true { setPhase(id, .finishing) }
            Task { [weak self] in
                await self?.settleTransportFailure(id, failure)
                self?.service.transport.acknowledge(taskID)
            }
        }
    }

    private func replayUnclaimedEvents(for taskID: Int) {
        for event in unclaimedEvents.removeValue(forKey: taskID) ?? [] {
            handle(event)
        }
    }

    /// Acknowledges finished events no upload claims, such as ones for an
    /// upload the outbox lost, so a background wake can end.
    private func dropUnclaimedEvents() {
        guard !isStartingTransfer else { return }
        let dropped = unclaimedEvents
        unclaimedEvents.removeAll()
        for (taskID, events) in dropped where events.contains(where: { if case .progress = $0 { false } else { true } }) {
            service.transport.acknowledge(taskID)
        }
    }

    // MARK: - Helpers

    func item(_ id: UUID) -> Item? {
        uploads.first { $0.id == id }
    }

    func title(of id: UUID) -> String {
        item(id)?.title ?? ""
    }

    func setPhase(_ id: UUID, _ phase: Item.Phase) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].phase = phase
    }

    func noteCompletion(_ completion: Completion) {
        if completion.succeeded { completedUploads += 1 }
        latestCompletion = completion
    }

    /// Called when an upload has ended either way.
    func finishRun(_ id: UUID) {
        if work?.itemID == id { work = nil }
        if records[id]?.leavesListWhenEnded == true { removeItem(id) }
        startNext()
    }

    /// Drops an upload from the list with its staged body and outbox entry,
    /// whatever its phase; the caller has made sure nothing of it still runs.
    func removeItem(_ id: UUID) {
        uploads.removeAll { $0.id == id }
        if latestCompletion?.itemID == id { latestCompletion = nil }
        guard let staged = records.removeValue(forKey: id)?.staged else { return }
        service.discard(staged)
        service.outbox.remove(id: staged.id)
    }
}
