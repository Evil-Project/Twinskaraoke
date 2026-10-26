import Foundation
nonisolated enum QRSignIn {

    enum Route {
        static var createSession: String { "\(StorageHost.api)/api/auth/qr-session" }

        static func status(_ sessionId: String) throws -> String {
            guard !sessionId.isEmpty, sessionId != ".", sessionId != "..",
                  let escaped = sessionId.addingPercentEncoding(
                    withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                  )
            else { throw ServiceError.invalidResponse }
            return "\(StorageHost.api)/api/auth/qr-session/\(escaped)"
        }
    }
    static let defaultLifetime: TimeInterval = 120

    struct Session: Equatable, Sendable {
        let id: String
        let payload: String
        var expiresAt: Date
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
                String(localized: "Couldn’t start a sign-in code. Try again.")
            case let .httpStatus(code):
                code == 429
                    ? String(localized: "Too many attempts. Wait a moment and try again.")
                    : String(localized: "Couldn’t reach Twinskaraoke (\(code)).")
            }
        }
    }

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
        let payload = decoded.qrCodePayload ?? decoded.approveUrl
        guard let payload, !payload.isEmpty else { throw ServiceError.invalidResponse }

        return Session(
            id: decoded.sessionId,
            payload: payload,
            expiresAt: decoded.expiresAt ?? Date().addingTimeInterval(defaultLifetime)
        )
    }

    static func status(of sessionId: String) async throws -> Poll {
        guard let url = URL(string: try Route.status(sessionId)) else {
            throw ServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
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
private nonisolated func parseTimestamp(_ raw: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]

    var normalized = raw
    if let dot = raw.firstIndex(of: "."),
       let end = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
    {
        let digits = raw[raw.index(after: dot) ..< end]
        if digits.count != 3 {
            let padded = digits.count > 3
                ? String(digits.prefix(3))
                : String(digits) + String(repeating: "0", count: 3 - digits.count)
            normalized = raw[..<dot] + "." + padded + raw[end...]
        }
    }

    return withFraction.date(from: normalized)
        ?? plain.date(from: normalized)
        ?? withFraction.date(from: raw)
        ?? plain.date(from: raw)
}
