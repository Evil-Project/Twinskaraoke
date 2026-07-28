import Foundation

/// Device pairing for the TV: the Apple TV has no camera, so it takes the role
/// the website plays in the existing QR flow. It asks the backend for a pairing
/// session, renders the session's payload as a QR code, and polls until a
/// signed-in phone scans it and calls `/api/auth/approve-qr` (see
/// `AuthManager.approveQRSession` in the iOS target, the other half of this
/// handshake).
///
/// # Backend contract
///
/// Verified against the live API:
///
/// - `POST {api}/api/auth/qr-session` — no body, no auth
///   ```
///   { "sessionId": "B53D…", "approveUrl": "…", "statusStreamUrl": "…",
///     "qrCodePayload": "https://api.neurokaraoke.com/auth/qr-approve?sessionId=B53D…",
///     "qrCodeImageDataUrl": "data:image/png;base64,…" }
///   ```
/// - `GET {api}/api/auth/qr-session/{sessionId}`
///   ```
///   { "status": "pending", "token": null, "expiresAt": "2026-07-28T14:53:13.80+00:00" }
///   ```
///   404 once the session is swept, with `{ "message": … }`.
///
/// The server also exposes an SSE stream at `statusStreamUrl` carrying the same
/// payload with PascalCase keys. Polling is used instead: a dropped stream on a
/// TV that may sit on flaky Wi-Fi is harder to recover from than a missed poll,
/// and the session is short-lived anyway.
///
/// `qrCodePayload` is encoded verbatim rather than rebuilt locally — it is
/// already an HTTPS URL on `api.neurokaraoke.com`, which the iOS scanner
/// accepts as a subdomain of the first-party host `neurokaraoke.com`
/// (`QRApproveView.trustedQRHosts`). Rebuilding it here would risk drifting out
/// of that allowlist.
nonisolated enum TVQRSignIn {
    // MARK: - Contract

    enum Route {
        static var createSession: String { "\(StorageHost.api)/api/auth/qr-session" }

        static func status(_ sessionId: String) -> String {
            let escaped = sessionId.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? sessionId
            return "\(StorageHost.api)/api/auth/qr-session/\(escaped)"
        }
    }

    /// Fallback lifetime for the window between creating a session and the
    /// first poll, which is where the server's own `expiresAt` arrives. A TV
    /// screen is a public display, so this stays short.
    static let defaultLifetime: TimeInterval = 120

    // MARK: - Types

    struct Session: Equatable, Sendable {
        let id: String
        /// Encoded into the QR verbatim; see the note on the type.
        let payload: String
        /// Provisional until the first poll replaces it with the server's value.
        var expiresAt: Date

        /// Shown next to the QR so the code on screen can be matched against
        /// the one the phone displays before approving. Matches the iOS side's
        /// `String(sessionId.prefix(8)).uppercased()`.
        var shortCode: String {
            String(id.prefix(8)).uppercased()
        }

        var isExpired: Bool { Date() >= expiresAt }
    }

    enum Status: Equatable, Sendable {
        case pending
        case approved(token: String)
        case expired
    }

    /// One poll. `expiresAt` is echoed on every response, so the TV keeps its
    /// countdown in step with the server rather than trusting its own clock
    /// arithmetic from creation time.
    struct Poll: Equatable, Sendable {
        let status: Status
        let expiresAt: Date?
    }

    enum ServiceError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case missingToken

        var errorDescription: String? {
            switch self {
            case .invalidResponse, .missingToken:
                "Couldn’t start a sign-in code. Try again."
            case let .httpStatus(code):
                code == 429
                    ? "Too many attempts. Wait a moment and try again."
                    : "Couldn’t reach Twinskaraoke (\(code))."
            }
        }
    }

    // MARK: - Requests

    static func createSession() async throws -> Session {
        guard let url = URL(string: Route.createSession) else {
            throw ServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ServiceError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(CreateResponse.self, from: data)
        guard !decoded.sessionId.isEmpty else { throw ServiceError.invalidResponse }

        // `approveUrl` is the documented fallback: the two fields carry the same
        // URL today, but only one of them is named for the job it does here.
        let payload = decoded.qrCodePayload ?? decoded.approveUrl
        guard let payload, !payload.isEmpty else { throw ServiceError.invalidResponse }

        return Session(
            id: decoded.sessionId,
            payload: payload,
            expiresAt: decoded.expiresAt ?? Date().addingTimeInterval(defaultLifetime)
        )
    }

    static func status(of sessionId: String) async throws -> Poll {
        guard let url = URL(string: Route.status(sessionId)) else {
            throw ServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        // A session the server has already swept is an expiry, not a failure.
        if http.statusCode == 404 || http.statusCode == 410 {
            return Poll(status: .expired, expiresAt: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ServiceError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(StatusResponse.self, from: data)
        let status: Status
        switch decoded.status.lowercased() {
        case "approved", "authorized", "complete", "completed":
            guard let token = decoded.token, !token.isEmpty else {
                throw ServiceError.missingToken
            }
            status = .approved(token: token)
        case "expired", "cancelled", "canceled", "rejected", "denied":
            status = .expired
        default:
            status = .pending
        }
        return Poll(status: status, expiresAt: decoded.expiresAt)
    }

    // MARK: - Wire shapes

    private struct CreateResponse: Decodable {
        let sessionId: String
        let qrCodePayload: String?
        let approveUrl: String?
        let expiresAt: Date?

        private enum CodingKeys: String, CodingKey {
            case sessionId, qrCodePayload, approveUrl, expiresAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
            qrCodePayload = try container.decodeIfPresent(String.self, forKey: .qrCodePayload)
            approveUrl = try container.decodeIfPresent(String.self, forKey: .approveUrl)
            expiresAt = try container
                .decodeIfPresent(String.self, forKey: .expiresAt)
                .flatMap(parseTimestamp)
        }
    }

    private struct StatusResponse: Decodable {
        let status: String
        let token: String?
        let expiresAt: Date?

        // The SSE stream sends the same payload PascalCased, so both spellings
        // are accepted and this shape can be reused if polling is ever swapped
        // for the stream.
        private enum CodingKeys: String, CodingKey {
            case status, Status
            case token, Token
            case expiresAt, ExpiresAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
                ?? container.decodeIfPresent(String.self, forKey: .Status)
                ?? "pending"
            token = try container.decodeIfPresent(String.self, forKey: .token)
                ?? container.decodeIfPresent(String.self, forKey: .Token)
            expiresAt = try (
                container.decodeIfPresent(String.self, forKey: .expiresAt)
                    ?? container.decodeIfPresent(String.self, forKey: .ExpiresAt)
            ).flatMap(parseTimestamp)
        }
    }
}

/// The API sends 7 fractional-second digits (`…:13.8019715+00:00`), which
/// `ISO8601DateFormatter` rejects outright on some OS versions rather than
/// truncating. Fractional digits are trimmed to three before parsing, and a
/// second pass drops them entirely in case the server ever stops sending them.
private func parseTimestamp(_ raw: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]

    var normalized = raw
    if let dot = raw.firstIndex(of: "."),
       let end = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
    {
        let digits = raw[raw.index(after: dot) ..< end]
        if digits.count > 3 {
            normalized = raw[..<dot] + "." + digits.prefix(3) + raw[end...]
        }
    }

    return withFraction.date(from: normalized)
        ?? plain.date(from: normalized)
        ?? withFraction.date(from: raw)
        ?? plain.date(from: raw)
}
