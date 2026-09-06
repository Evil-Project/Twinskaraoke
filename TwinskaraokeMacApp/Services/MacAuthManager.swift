import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security

/// On macOS `ASPresentationAnchor` is an `NSWindow`, where iOS uses a `UIWindow`.
/// That difference is the whole reason this flow needed porting rather than
/// sharing — the rest of the OAuth exchange is platform-neutral.
private final class WebAuthPresentationContextProvider:
    NSObject, ASWebAuthenticationPresentationContextProviding
{
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

/// Sign-in and account state for the Mac app.
///
/// Offers all three routes the other targets have between them:
/// - QR device pairing (the default), ported from `TVAuthManager`
/// - Username/password against `/api/auth/login`, as on iOS
/// - Discord OAuth via `ASWebAuthenticationSession` with an `NSWindow` anchor
///
/// All three land on the same Keychain-backed `CredentialStore`, and the
/// profile/badge/upload-limit fetch mirrors `TVAuthManager.refreshAccount`.
@MainActor
@Observable
final class MacAuthManager {
    static let shared = MacAuthManager()

    private(set) var isLoggedIn = false
    private(set) var username: String?
    private(set) var userID: String?
    private(set) var avatar: String?
    private(set) var isLoading = false
    var errorMessage: String?

    private var webAuthSession: ASWebAuthenticationSession?
    private var webAuthContextProvider: WebAuthPresentationContextProvider?

    // MARK: - Profile

    private(set) var profile: UserProfile?
    private(set) var badges: [AccountBadge] = []
    private(set) var uploadLimits: UploadLimits?
    private(set) var isRefreshingProfile = false
    private(set) var profileError: String?

    /// Fetches profile, badges and upload limits. Mirrors
    /// `TVAuthManager.refreshAccount` — same endpoints, same partial-failure
    /// handling, so one endpoint being down doesn't blank the whole screen.
    func refreshAccount() async {
        guard isLoggedIn, let token = CredentialStore.token, !isRefreshingProfile else { return }
        isRefreshingProfile = true
        profileError = nil
        defer { isRefreshingProfile = false }

        async let fetchedProfile = try? Self.authorizedData(path: "/api/badge/profile")
        async let fetchedLimits = try? Self.authorizedData(path: "/api/user/upload-limits")
        let (profileData, limitsData) = await (fetchedProfile, fetchedLimits)
        guard !Task.isCancelled, isLoggedIn, CredentialStore.token == token else { return }

        var didFail = false
        if let profileData {
            do {
                let response = try JSONDecoder().decode(ProfileResponse.self, from: profileData)
                profile = response.profile
                badges = response.badges ?? []
                if let avatarUrl = response.profile.avatarUrl, !avatarUrl.isEmpty {
                    avatar = avatarUrl
                }
            } catch {
                didFail = true
            }
        } else {
            didFail = true
        }

        if let limitsData {
            do {
                uploadLimits = try JSONDecoder().decode(UploadLimits.self, from: limitsData)
            } catch {
                didFail = true
            }
        } else {
            didFail = true
        }

        if didFail {
            profileError = "Some account details couldn't be refreshed. Try again."
        }
    }

    private static func authorizedData(path: String) async throws -> Data {
        let request = try KaraokeAPIClient.request(path: path)
        return try await KaraokeAPIClient.data(for: request)
    }

    /// Resolved avatar for the toolbar button and profile header. Prefers the
    /// profile payload, falling back to the stored avatar claim.
    ///
    /// The fallback cannot just be `URL(string:)`: `parseJWT` returns the raw
    /// `urn:discord:avatar` claim, which is a bare hash or a storage-relative
    /// path rather than an absolute URL. Only the Discord OAuth path stores a
    /// full CDN URL, so password sign-in, QR sign-in and session restore all
    /// showed the placeholder. Same resolution `UserProfile.avatarURL` uses.
    var avatarURL: URL? {
        if let profile, let url = profile.avatarURL { return url }
        guard let avatar, !avatar.isEmpty else { return nil }
        if let url = URL(string: avatar), url.scheme != nil { return url }
        // A bare 32-hex Discord avatar hash needs the user id to form a CDN URL.
        if let userID, Self.looksLikeDiscordAvatarHash(avatar) {
            return URL(string: "https://cdn.discordapp.com/avatars/\(userID)/\(avatar).png")
        }
        return URL(string: "\(StorageHost.base)\(ArtworkURLBuilder.normalizedPath(avatar))")
    }

    private static func looksLikeDiscordAvatarHash(_ value: String) -> Bool {
        let trimmed = value.hasPrefix("a_") ? String(value.dropFirst(2)) : value
        return trimmed.count == 32 && trimmed.allSatisfy(\.isHexDigit)
    }

    // MARK: - QR pairing state

    private(set) var qrSession: QRSignIn.Session?
    private(set) var qrPhase: QRPhase = .idle
    private(set) var qrError: String?
    @ObservationIgnored private var qrTask: Task<Void, Never>?

    enum QRPhase: Equatable {
        case idle
        case creating
        case waiting
        case completing
        case expired
    }

    private enum Endpoint {
        static var login: String { "\(StorageHost.api)/api/auth/login" }
        static var nkTokenExchange: String { "\(StorageHost.idk)/api/auth/discord-token" }

        static let discordAuth = "https://discord.com/oauth2/authorize"
        static let discordToken = "https://discord.com/api/oauth2/token"
        static let discordUser = "https://discord.com/api/users/@me"
        static let discordClientId = "1447802634621943850"
        static let redirectUri = "neurokaraoke://auth"
        static let callbackScheme = "neurokaraoke"
    }

    // nonisolated: referenced from the ASWebAuthenticationSession completion
    // handler, which macOS invokes on a background XPC queue.
    private nonisolated enum AuthError: LocalizedError {
        case http(Int, String)
        case parse
        case invalidCallback
        case cancelled

        var errorDescription: String? {
            switch self {
            case .http(401, _): "Incorrect username or password."
            case .http(let code, _): "The server returned an error (\(code))."
            case .parse: "Couldn't read the server's response."
            case .invalidCallback: "Authentication failed — please try again."
            case .cancelled: ""
            }
        }
    }

    private init() {
        restoreSession()
    }

    private func restoreSession() {
        guard let token = CredentialStore.token, !token.isEmpty else { return }
        let claims = Self.parseJWT(token)
        isLoggedIn = true
        userID = claims?.id
        username = claims?.username
        avatar = claims?.avatar
    }

    func login(username rawUsername: String, password: String) async {
        let trimmed = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let url = URL(string: Endpoint.login) else { throw AuthError.parse }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            // Without this the request inherits URLSession's 60s default, so a
            // stalled connection leaves the sign-in button spinning for a
            // minute. Every other request in this file bounds itself.
            request.timeoutInterval = Self.requestTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["username": trimmed, "password": password]
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw AuthError.http(status, String(data: data, encoding: .utf8) ?? "")
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = json["token"] as? String
            else { throw AuthError.parse }

            try CredentialStore.saveToken(token)
            let claims = Self.parseJWT(token)
            isLoggedIn = true
            userID = claims?.id ?? trimmed
            self.username = claims?.username ?? trimmed
            avatar = claims?.avatar

            FavoritesManager.shared.reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Discord OAuth

    func loginWithDiscord() async {
        guard webAuthSession == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let anchor = Self.activePresentationAnchor() else {
                throw AuthError.invalidCallback
            }
            let verifier = Self.makeVerifier()
            let state = Self.makeVerifier()

            var components = URLComponents(string: Endpoint.discordAuth)!
            components.queryItems = [
                .init(name: "client_id", value: Endpoint.discordClientId),
                .init(name: "redirect_uri", value: Endpoint.redirectUri),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: "identify"),
                .init(name: "code_challenge", value: Self.makeChallenge(verifier)),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state),
            ]
            guard let authURL = components.url else { throw AuthError.invalidCallback }

            let callbackURL = try await presentWebAuth(url: authURL, anchor: anchor)

            // Reject a callback whose state doesn't match the one we generated:
            // that is the CSRF guard PKCE relies on.
            guard
                let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                callback.queryItems?.first(where: { $0.name == "state" })?.value == state,
                let code = callback.queryItems?.first(where: { $0.name == "code" })?.value
            else { throw AuthError.invalidCallback }

            let discordToken = try await exchangeDiscordCode(code, verifier: verifier)
            let nkToken = try await exchangeForNKToken(discordToken)
            let profile = try await fetchDiscordProfile(discordToken)

            try CredentialStore.saveToken(nkToken)
            isLoggedIn = true
            userID = profile.id
            username = profile.username
            avatar = profile.avatar
            FavoritesManager.shared.reload()
        } catch {
            webAuthSession = nil
            webAuthContextProvider = nil
            // A user-cancelled sheet isn't an error worth showing.
            if case AuthError.cancelled = error { return }
            if Self.isCancellation(error) { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func presentWebAuth(url: URL, anchor: ASPresentationAnchor) async throws -> URL {
        // Clearing the session here rather than inside the completion handler:
        // control is back on the main actor once the continuation resumes, so
        // the handler itself never has to touch isolated state.
        defer {
            webAuthSession = nil
            webAuthContextProvider = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Endpoint.callbackScheme
            ) { @Sendable callbackURL, error in
                // macOS calls this on an XPC queue, not the main thread — iOS
                // calls it on the main thread, which is why the iOS AuthManager
                // gets away with the same shape. @Sendable forces the closure
                // nonisolated, so Swift 6 doesn't insert a main-actor check
                // that would trap here (EXC_BREAKPOINT).
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthError.cancelled)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            let provider = WebAuthPresentationContextProvider(anchor: anchor)
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = true
            webAuthContextProvider = provider
            webAuthSession = session

            guard session.start() else {
                webAuthSession = nil
                webAuthContextProvider = nil
                continuation.resume(throwing: AuthError.invalidCallback)
                return
            }
        }
    }

    private func exchangeDiscordCode(_ code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: Endpoint.discordToken)!)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let redirect = Endpoint.redirectUri
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Endpoint.redirectUri
        request.httpBody = """
            client_id=\(Endpoint.discordClientId)\
            &grant_type=authorization_code\
            &code=\(code)\
            &redirect_uri=\(redirect)\
            &code_verifier=\(verifier)
            """.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String
        else { throw AuthError.parse }
        return accessToken
    }

    private func exchangeForNKToken(_ discordToken: String) async throws -> String {
        // nkTokenExchange interpolates StorageHost.idk, which is resolved at
        // runtime — unlike the literal Discord endpoints, it can be malformed,
        // and force-unwrapping it would crash rather than surface an error.
        guard let url = URL(string: Endpoint.nkTokenExchange) else { throw AuthError.parse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["accessToken": discordToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        guard let token = Self.exchangedToken(from: data) else { throw AuthError.parse }
        return token
    }

    private struct DiscordProfile {
        let id: String
        let username: String
        let avatar: String?
    }

    private func fetchDiscordProfile(_ token: String) async throws -> DiscordProfile {
        var request = URLRequest(url: URL(string: Endpoint.discordUser)!)
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.parse
        }
        let id = json["id"] as? String ?? ""
        let name = json["global_name"] as? String ?? json["username"] as? String ?? ""
        let avatarID = json["avatar"] as? String
        return DiscordProfile(
            id: id,
            username: name,
            avatar: avatarID.map { "https://cdn.discordapp.com/avatars/\(id)/\($0).png" }
        )
    }

    func logout() {
        // A live pairing code outliving sign-out could complete behind the
        // user and silently sign them back in.
        cancelQRSignIn()
        CredentialStore.deleteToken()
        isLoggedIn = false
        username = nil
        userID = nil
        avatar = nil
        errorMessage = nil
        profile = nil
        badges = []
        uploadLimits = nil
        profileError = nil
        FavoritesManager.shared.clear()
    }

    // MARK: - QR device pairing

    /// Requests a pairing code and polls until a signed-in phone approves it.
    /// Safe to call repeatedly; any in-flight attempt is replaced. Ported from
    /// `TVAuthManager` — the Mac has a keyboard, but pairing from a phone that
    /// is already signed in is still the fastest way in.
    func startQRSignIn() {
        qrTask?.cancel()
        qrError = nil
        qrSession = nil
        qrPhase = .creating
        qrTask = Task { [weak self] in
            await self?.runQRSignIn()
        }
    }

    func cancelQRSignIn() {
        qrTask?.cancel()
        qrTask = nil
        qrSession = nil
        qrPhase = .idle
        qrError = nil
    }

    private func runQRSignIn() async {
        var session: QRSignIn.Session
        do {
            session = try await QRSignIn.createSession()
        } catch {
            guard !Task.isCancelled else { return }
            qrError = Self.friendlyMessage(for: error)
            qrPhase = .idle
            return
        }

        guard !Task.isCancelled else { return }
        qrSession = session
        qrPhase = .waiting

        let start = Date()
        // A single network blip shouldn't discard a code the user is already
        // pointing a phone at; only give up after it keeps failing.
        var consecutiveFailures = 0

        while !Task.isCancelled {
            if session.isExpired {
                qrPhase = .expired
                return
            }

            // Tight while the user is most likely mid-scan, slower after.
            let interval: Double = Date().timeIntervalSince(start) < 30 ? 2 : 5
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }

            do {
                let poll = try await QRSignIn.status(of: session.id)
                guard !Task.isCancelled, qrSession?.id == session.id else { return }
                // The server owns the deadline; the value from createSession is
                // only a placeholder until the first poll lands.
                if let expiresAt = poll.expiresAt, expiresAt != session.expiresAt {
                    session.expiresAt = expiresAt
                    qrSession = session
                }

                switch poll.status {
                case .pending:
                    consecutiveFailures = 0
                case .expired:
                    qrPhase = .expired
                    return
                case let .approved(token):
                    qrPhase = .completing
                    completeQRSignIn(token: token)
                    return
                }
            } catch {
                guard !Task.isCancelled, qrSession?.id == session.id else { return }
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    qrError = Self.friendlyMessage(for: error)
                    qrPhase = .idle
                    return
                }
            }
        }
    }

    private func completeQRSignIn(token: String) {
        // Without readable claims the session would persist with an empty
        // username, so fail loudly rather than half-committing.
        guard let claims = Self.parseJWT(token) else {
            qrError = "That sign-in couldn't be completed. Try again."
            qrPhase = .idle
            return
        }
        do {
            try CredentialStore.saveToken(token)
        } catch {
            // Include the OSStatus: a bare "couldn't save" gave no way to tell
            // a Keychain entitlement problem from a transient failure.
            if case CredentialStore.StoreError.keychain(let status) = error {
                qrError = "Couldn't save your sign-in (Keychain error \(status))."
            } else {
                qrError = "Couldn't save your sign-in. Try again."
            }
            qrPhase = .idle
            return
        }
        isLoggedIn = true
        userID = claims.id
        username = claims.username
        avatar = claims.avatar
        qrSession = nil
        qrPhase = .idle
        // A transient poll failure earlier in this run may have set qrError;
        // leaving it would show a stale error beside a signed-in account.
        qrError = nil
        FavoritesManager.shared.reload()
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let serviceError = error as? QRSignIn.ServiceError {
            return serviceError.errorDescription ?? "Something went wrong. Try again."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Helpers

    private static let requestTimeout: TimeInterval = 15

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.http(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASWebAuthenticationSessionErrorDomain
            && nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
    }

    /// macOS equivalent of the iOS anchor lookup: a key `NSWindow` instead of a
    /// key `UIWindow` from the connected scenes.
    private static func activePresentationAnchor() -> ASPresentationAnchor? {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first
    }

    private static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func makeChallenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The exchange endpoint has returned a bare string, a quoted JSON string
    /// and an object across versions, so accept all three — same handling as
    /// `AuthManager.exchangedToken(from:)` on iOS.
    static func exchangedToken(from data: Data) -> String? {
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            if let object = json as? [String: Any] {
                return validatedToken(object["token"] as? String ?? object["accessToken"] as? String)
            }
            if let string = json as? String {
                return validatedToken(string)
            }
            return nil
        }
        return validatedToken(raw)
    }

    private static func validatedToken(_ candidate: String?) -> String? {
        guard let token = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              token.utf8.count <= 8_192
        else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~+/="))
        guard token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return token
    }

    /// Same claim URIs the iOS target reads — the token is issued by one server
    /// for every platform, so the shapes must not drift.
    private static func parseJWT(_ jwt: String) -> (id: String, username: String, avatar: String?)? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        base64 = base64.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard
            let data = Data(base64Encoded: base64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let id = json["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"] as? String ?? ""
        let name = json["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"] as? String ?? ""
        let avatar = (json["urn:discord:avatar"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard !id.isEmpty, !name.isEmpty else { return nil }
        return (id, name, avatar)
    }
}
