import Foundation

/// How an upload ends: the server's answer, a transport failure, or neither.
extension SongUploadController {
    /// The server's answer to a transfer, as the transport reports it.
    struct ServerAnswer {
        let status: Int
        let body: Data
        let contentType: String?
        let retryAfter: TimeInterval?
    }

    /// The server answered the upload. Success has an empty body and no id.
    func settleAnswer(_ id: UUID, settlement: Int, _ answer: ServerAnswer) async {
        let (status, body, contentType, retryAfter) = (answer.status, answer.body, answer.contentType, answer.retryAfter)
        DebugLogger.log("Upload answered: HTTP \(status), \(body.count) bytes", category: .network)
        switch status {
        case 200..<300:
            await succeed(id, title: title(of: id), settlement: settlement)
        case 401:
            setPhase(id, .finishing)
            let resolved = await unauthorizedFailure(UploadServerProblem.parse(data: body, contentType: contentType))
            fail(id, resolved, settlement: settlement)
        case 429:
            fail(id, .rateLimited(retryAfter: retryAfter), settlement: settlement)
        case 500...:
            // A gateway can time out after the server stored the song.
            let problem = UploadServerProblem.parse(data: body, contentType: contentType)
            await settleAmbiguous(id, failure: .server(status: status, problem: problem), settlement: settlement)
        default:
            let problem = UploadServerProblem.parse(data: body, contentType: contentType)
            fail(id, .server(status: status, problem: problem), settlement: settlement)
        }
    }

    /// A failure after which the song may still have been added: the request
    /// was lost or timed out, or a gateway answered for the server.
    static func mayHaveLanded(_ failure: SongUploadFailure) -> Bool {
        switch failure {
        case .timedOut, .interrupted: true
        case let .server(status, _): status >= 500
        default: false
        }
    }

    /// Errors that mean the request never reached the server, as
    /// `KaraokeAPIClient` classifies them for the other upload writes.
    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
    ]

    /// The transfer ended without an answer.
    func settleTransportFailure(_ id: UUID, _ failure: UploadTransport.Failure, settlement: Int) async {
        switch failure {
        case let .urlError(code) where Self.offlineCodes.contains(code):
            DebugLogger.log("Upload failed offline", category: .network)
            fail(id, .offline, settlement: settlement)
        case .urlError(.timedOut):
            DebugLogger.log("Upload timed out", category: .network)
            await settleAmbiguous(id, failure: .timedOut, settlement: settlement)
        case let .urlError(code):
            DebugLogger.log("Upload lost: URLError \(code.rawValue)", category: .network)
            await settleAmbiguous(id, failure: .interrupted, settlement: settlement)
        case .cancelled:
            // Not the user: they remove the upload before cancelling it.
            await settleAmbiguous(id, failure: .interrupted, settlement: settlement)
        }
    }

    /// Loads the user's uploads before anything is sent, so an ending that
    /// doesn't say whether the song arrived can be settled later. Without
    /// that list a retry could add the song twice, so when it can't be
    /// loaded `id` fails before anything is sent. Returns whether it loaded.
    func loadBaseline(_ id: UUID) async -> Bool {
        // The list is the signed-in account's: not one to compare with later.
        guard !refuseForAnotherAccount(id) else { return false }
        do {
            let known = try await Set(service.uploadedSongTitles().keys)
            guard records[id] != nil else { return false }
            records[id]?.knownSongIDs = known
            return true
        } catch {
            guard !Task.isCancelled, records[id] != nil else { return false }
            DebugLogger.log("Upload not sent: the uploads list failed to load", category: .network)
            fail(id, Self.baselineFailure(error))
            return false
        }
    }

    /// A retryable failure for a list that couldn't be loaded: offline for a
    /// connectivity error, else the server's status or an interruption.
    static func baselineFailure(_ error: Error) -> SongUploadFailure {
        switch error {
        case let urlError as URLError where offlineCodes.contains(urlError.code):
            .offline
        case let urlError as URLError where urlError.code == .timedOut:
            .timedOut
        case let failure as SongUploadFailure:
            failure
        case let KaraokeAPIClient.APIError.httpStatus(status) where status >= 500:
            .server(status: status, problem: nil)
        default:
            .interrupted
        }
    }

    /// The body may or may not have arrived. The server's answer carries no
    /// id, so a song in the user's uploads that wasn't there before, and that
    /// `isThisUpload` matches, means it did; otherwise the user can try again.
    func settleAmbiguous(_ id: UUID, failure: SongUploadFailure, settlement: Int) async {
        guard ownsSettlement(id, settlement) else { return }
        setPhase(id, .finishing)
        if await reconcileFindsNothing(id, failure: failure, settlement: settlement) {
            fail(id, failure, settlement: settlement)
        }
    }

    /// A retry of an upload whose ending the list couldn't settle: the list
    /// is asked again before anything is sent, since the first body may have
    /// landed. Returns whether it may be sent again. Nothing of this is
    /// persisted: a failed upload leaves the outbox, and its staged body is
    /// swept at the next launch, so it can't be retried after a relaunch.
    func confirmNotLanded(_ id: UUID) async -> Bool {
        guard let failure = records[id]?.unconfirmed else { return true }
        let settlement = beginSettlement(id)
        setPhase(id, .finishing)
        guard await reconcileFindsNothing(id, failure: failure, settlement: settlement) else { return false }
        records[id]?.unconfirmed = nil
        records[id]?.settling = false
        return true
    }

    /// Matches `id` against the uploads list. Returns `true` when the list
    /// loaded without it; otherwise `id` has ended: it succeeded, or failed
    /// with `failure` and stays unconfirmed when the list couldn't load, or
    /// it wasn't this account's to match.
    private func reconcileFindsNothing(_ id: UUID, failure: SongUploadFailure, settlement: Int) async -> Bool {
        guard mayReconcile(id, settlement: settlement) else { return false }
        guard let known = records[id]?.knownSongIDs else { return true }
        let current: [String: String]
        do {
            current = try await service.uploadedSongTitles()
        } catch {
            guard ownsSettlement(id, settlement) else { return false }
            DebugLogger.log("Upload not settled: the uploads list failed to load", category: .network)
            records[id]?.unconfirmed = failure
            fail(id, failure, settlement: settlement)
            return false
        }
        guard ownsSettlement(id, settlement) else { return false }
        guard isThisUpload(id, added: current.filter { !known.contains($0.key) }.map(\.value)) else { return true }
        await succeed(id, title: title(of: id), settlement: settlement)
        return false
    }

    /// Claims the settlement of `id`. A later claim, such as the server's
    /// answer arriving while a vanished upload is being matched, takes over:
    /// the earlier one's ending is ignored.
    func beginSettlement(_ id: UUID) -> Int {
        records[id]?.settlement += 1
        records[id]?.settling = true
        return records[id]?.settlement ?? 0
    }

    func ownsSettlement(_ id: UUID, _ settlement: Int?) -> Bool {
        guard let record = records[id] else { return false }
        return settlement.map { $0 == record.settlement } ?? true
    }

    /// Whether `added`, the titles of songs new since `id` started, holds it.
    /// A file upload sends its title, so only a song with that title counts,
    /// not one another device added meanwhile. A link's title isn't known
    /// until the server answers, so for a link (or a file sent without a
    /// title) any new song counts.
    private func isThisUpload(_ id: UUID, added: [String]) -> Bool {
        guard !added.isEmpty else { return false }
        let sent = SongUploadMetadata(title: title(of: id), artist: "", playlistID: nil)
            .formFields.first { $0.name == "Title" }?.value
        guard item(id)?.kind == .file, let sent else { return true }
        return added.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == sent }
    }

    /// A 401 can be an expired session or the upload host refusing the
    /// token. One read on the main API tells: if that is refused too, the
    /// shared session-expiry path signs the user out.
    func unauthorizedFailure(_ problem: UploadServerProblem?) async -> SongUploadFailure {
        do {
            _ = try await service.limits()
            return .server(status: 401, problem: problem)
        } catch KaraokeAPIClient.APIError.httpStatus(401), SongUploadFailure.signedOut {
            return .signedOut
        } catch {
            return .server(status: 401, problem: problem)
        }
    }

    /// Ends `id` as added, once per run; `settlement`, when given, must
    /// still be the current one.
    func succeed(_ id: UUID, title: String, settlement: Int? = nil) async {
        guard let record = records[id], !record.ended, ownsSettlement(id, settlement) else { return }
        guard !record.endsUnseen else { return endUnseen(id) }
        records[id]?.ended = true
        clearTransfer(id, discardingStage: true)
        await service.invalidateUploads()
        guard let record = records[id] else { return }
        guard !record.endsUnseen else { return endUnseen(id) }
        setPhase(id, .succeeded(title: title))
        noteCompletion(Completion(itemID: id, title: title, succeeded: true))
        DebugLogger.log("Upload succeeded", category: .network)
        finishRun(id)
    }

    /// Keeps the staged body, so a retry can send it again. Once per run,
    /// as `succeed`.
    func fail(_ id: UUID, _ failure: SongUploadFailure, settlement: Int? = nil) {
        guard let record = records[id], !record.ended, ownsSettlement(id, settlement) else { return }
        guard !record.endsUnseen else { return endUnseen(id) }
        records[id]?.ended = true
        clearTransfer(id, discardingStage: false)
        setPhase(id, .failed(failure))
        noteCompletion(Completion(itemID: id, title: title(of: id), succeeded: false))
        DebugLogger.log("Upload failed: \(Self.logReason(failure))", category: .network)
        finishRun(id)
    }

    private func clearTransfer(_ id: UUID, discardingStage: Bool) {
        records[id]?.taskID = nil
        guard let staged = records[id]?.staged else { return }
        service.outbox.remove(id: staged.id)
        if discardingStage {
            service.discard(staged)
            records[id]?.staged = nil
        }
    }

    /// Status codes and kinds only; server messages may echo user data.
    private static func logReason(_ failure: SongUploadFailure) -> String {
        switch failure {
        case let .server(status, _): "HTTP \(status)"
        case .quotaSongs: "song quota"
        case .quotaStorage: "storage quota"
        case .unsupportedLink: "unsupported link"
        default: "\(failure)"
        }
    }
}
