import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
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

private nonisolated final class WebAuthContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

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

    @ObservationIgnored private var loginGeneration = UUID()
    @ObservationIgnored private var webAuthContinuation: CheckedContinuation<URL, Error>?
    private var webAuthSession: ASWebAuthenticationSession?
    private var webAuthContextProvider: WebAuthPresentationContextProvider?
    @ObservationIgnored private var sessionRevision = 0
    @ObservationIgnored private var profileRefreshRevision = 0

    private(set) var profile: UserProfile?
    private(set) var badges: [AccountBadge] = []
    private(set) var uploadLimits: UploadLimits?
    private(set) var isRefreshingProfile = false
    private(set) var profileError: String?
    func refreshAccount() async {
        guard isLoggedIn, let token = CredentialStore.token, !isRefreshingProfile else { return }
        let authenticatedRevision = sessionRevision
        profileRefreshRevision &+= 1
        let refreshRevision = profileRefreshRevision
        isRefreshingProfile = true
        profileError = nil
        defer {
            if profileRefreshRevision == refreshRevision {
                isRefreshingProfile = false
            }
        }

        async let fetchedProfile = try? Self.authorizedData(path: "/api/badge/profile")
        async let fetchedLimits = try? Self.authorizedData(path: "/api/user/upload-limits")
        let (profileData, limitsData) = await (fetchedProfile, fetchedLimits)
        guard !Task.isCancelled, isLoggedIn, CredentialStore.token == token else { return }

        guard !Task.isCancelled,
              sessionRevision == authenticatedRevision,
              isLoggedIn,
              CredentialStore.token == token
        else { return }

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
            profileError = String(localized: "Some account details couldn't be refreshed. Try again.")
        }
    }

    private static func authorizedData(path: String) async throws -> Data {
        let request = try KaraokeAPIClient.request(path: path)
        return try await KaraokeAPIClient.data(for: request)
    }
    var avatarURL: URL? {
        if let profile, let url = profile.avatarURL { return url }
        guard let avatar, !avatar.isEmpty else { return nil }
        if let url = URL(string: avatar), url.scheme != nil { return url }
        if let userID, Self.looksLikeDiscordAvatarHash(avatar) {
            return URL(string: "https://cdn.discordapp.com/avatars/\(userID)/\(avatar).png")
        }
        return URL(string: "\(StorageHost.base)\(ArtworkURLBuilder.normalizedPath(avatar))")
    }

    private static func looksLikeDiscordAvatarHash(_ value: String) -> Bool {
        let trimmed = value.hasPrefix("a_") ? String(value.dropFirst(2)) : value
        return trimmed.count == 32 && trimmed.allSatisfy(\.isHexDigit)
    }

    private(set) var qrSession: QRSignIn.Session?
    private(set) var qrPhase: QRPhase = .idle
    private(set) var qrError: String?
    @ObservationIgnored private var qrTask: Task<Void, Never>?
    @ObservationIgnored private var qrGeneration = 0

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
    private nonisolated enum AuthError: LocalizedError {
        case http(Int, String)
        case parse
        case invalidCallback
        case cancelled

        var errorDescription: String? {
            switch self {
            case .http(401, _): String(localized: "Incorrect username or password.")
            case .http(let code, _): String(localized: "The server returned an error (\(code)).")
            case .parse: String(localized: "Couldn't read the server's response.")
            case .invalidCallback: String(localized: "Authentication failed — please try again.")
            case .cancelled: ""
            }
        }
    }

    @ObservationIgnored private var sessionExpiredObserver: NSObjectProtocol?

    private init() {
        restoreSession()
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: .karaokeSessionExpired, object: nil, queue: .main
        ) { [weak self] note in
            let expiredToken = note.userInfo?["requestToken"] as? String
            Task { @MainActor [weak self] in
                guard let self, let expiredToken, CredentialStore.token == expiredToken else { return }
                self.logout()
                self.errorMessage = String(localized: "Your session expired — please sign in again")
            }
        }
    }

    isolated deinit {
        if let sessionExpiredObserver { NotificationCenter.default.removeObserver(sessionExpiredObserver) }
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
        guard !isLoading else { return }
        let trimmed = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "Please fill in all fields.")
            return
        }

        cancelQRSignIn()
        let generation = UUID()
        loginGeneration = generation
        isLoading = true
        errorMessage = nil
        defer { if loginGeneration == generation { isLoading = false } }

        do {
            guard let url = URL(string: Endpoint.login) else { throw AuthError.parse }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = Self.requestTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["username": trimmed, "password": password]
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard loginGeneration == generation else { return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw AuthError.http(status, String(data: data, encoding: .utf8) ?? "")
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = json["token"] as? String
            else { throw AuthError.parse }
            try Task.checkCancellation()

            try CredentialStore.saveToken(token)
            let claims = Self.parseJWT(token)
            beginAuthenticatedSession(
                userID: claims?.id ?? trimmed,
                username: claims?.username ?? trimmed,
                avatar: claims?.avatar
            )

            FavoritesManager.shared.reload()
        } catch {
            guard loginGeneration == generation else { return }
            if Task.isCancelled || Self.isCancellation(error) { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loginWithDiscord() async {
        guard !isLoading, webAuthSession == nil else { return }
        cancelQRSignIn()
        let generation = UUID()
        loginGeneration = generation
        isLoading = true
        errorMessage = nil
        defer { if loginGeneration == generation { isLoading = false } }

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
            try Task.checkCancellation()
            guard loginGeneration == generation else { return }

            // Reject a callback whose state doesn't match the one we generated:
            // that is the CSRF guard PKCE relies on.
            guard
                let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                callback.queryItems?.first(where: { $0.name == "state" })?.value == state,
                let code = callback.queryItems?.first(where: { $0.name == "code" })?.value
            else { throw AuthError.invalidCallback }

            let discordToken = try await exchangeDiscordCode(code, verifier: verifier)
            try Task.checkCancellation()
            guard loginGeneration == generation else { return }
            let nkToken = try await exchangeForNKToken(discordToken)
            try Task.checkCancellation()
            guard loginGeneration == generation else { return }
            let profile = try await fetchDiscordProfile(discordToken)
            try Task.checkCancellation()
            guard loginGeneration == generation else { return }

            try CredentialStore.saveToken(nkToken)
            beginAuthenticatedSession(
                userID: profile.id,
                username: profile.username,
                avatar: profile.avatar
            )
            FavoritesManager.shared.reload()
        } catch {
            guard loginGeneration == generation else { return }
            if Task.isCancelled || Self.isCancellation(error) { return }
            webAuthSession = nil
            webAuthContextProvider = nil
            if Task.isCancelled { return }
            if case AuthError.cancelled = error { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func presentWebAuth(url: URL, anchor: ASPresentationAnchor) async throws -> URL {
        let generation = loginGeneration
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                webAuthContinuation = continuation
                let session = ASWebAuthenticationSession(
                    url: url, callback: .customScheme(Endpoint.callbackScheme)
                ) { @Sendable [weak self] callbackURL, error in
                    // The system callback may run on an XPC queue.
                    Task { @MainActor [weak self] in
                        guard let self, loginGeneration == generation else { return }
                        if let error {
                            finishWebAuth(.failure(error))
                        } else if let callbackURL {
                            finishWebAuth(.success(callbackURL))
                        } else {
                            finishWebAuth(.failure(AuthError.cancelled))
                        }
                    }
                }
                let provider = WebAuthPresentationContextProvider(anchor: anchor)
                session.presentationContextProvider = provider
                session.prefersEphemeralWebBrowserSession = true
                webAuthContextProvider = provider
                webAuthSession = session
                if !session.start() {
                    finishWebAuth(.failure(AuthError.invalidCallback))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, loginGeneration == generation else { return }
                cancelWebAuth()
            }
        }
    }

    private func finishWebAuth(_ result: Result<URL, Error>) {
        let continuation = webAuthContinuation
        webAuthContinuation = nil
        webAuthSession = nil
        webAuthContextProvider = nil
        continuation?.resume(with: result)
    }

    private func cancelWebAuth() {
        webAuthSession?.cancel()
        finishWebAuth(.failure(CancellationError()))
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
        loginGeneration = UUID()
        cancelWebAuth()
        isLoading = false
        // A live pairing code outliving sign-out could complete behind the
        // user and silently sign them back in.
        cancelQRSignIn()
        webAuthSession?.cancel()
        webAuthSession = nil
        webAuthContextProvider = nil
        sessionRevision &+= 1
        profileRefreshRevision &+= 1
        isRefreshingProfile = false
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
    func startQRSignIn() {
        guard !isLoading else { return }
        qrTask?.cancel()
        qrGeneration &+= 1
        let generation = qrGeneration
        qrError = nil
        qrSession = nil
        qrPhase = .creating
        qrTask = Task { [weak self] in
            await self?.runQRSignIn(generation: generation)
        }
    }

    func cancelQRSignIn() {
        qrGeneration &+= 1
        qrTask?.cancel()
        qrTask = nil
        qrSession = nil
        qrPhase = .idle
        qrError = nil
    }

    private func runQRSignIn(generation: Int) async {
        defer {
            if qrGeneration == generation {
                qrTask = nil
            }
        }
        var session: QRSignIn.Session
        do {
            session = try await QRSignIn.createSession()
        } catch {
            guard !Task.isCancelled, qrGeneration == generation else { return }
            qrError = Self.friendlyMessage(for: error)
            qrPhase = .idle
            return
        }

        guard !Task.isCancelled, qrGeneration == generation else { return }
        qrSession = session
        qrPhase = .waiting

        let start = Date()
        var consecutiveFailures = 0

        while !Task.isCancelled, qrGeneration == generation {
            if session.isExpired {
                qrPhase = .expired
                return
            }
            let interval: Double = Date().timeIntervalSince(start) < 30 ? 2 : 5
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, qrGeneration == generation else { return }

            do {
                let poll = try await QRSignIn.status(of: session.id)
                guard !Task.isCancelled,
                      qrGeneration == generation,
                      qrSession?.id == session.id
                else { return }
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
                    completeQRSignIn(token: token, generation: generation)
                    return
                }
            } catch {
                guard !Task.isCancelled,
                      qrGeneration == generation,
                      qrSession?.id == session.id
                else { return }
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    qrError = Self.friendlyMessage(for: error)
                    qrPhase = .idle
                    return
                }
            }
        }
    }

    private func completeQRSignIn(token: String, generation: Int) {
        guard qrGeneration == generation else { return }
        guard let claims = Self.parseJWT(token) else {
            qrError = "That sign-in couldn't be completed. Try again."
            qrPhase = .idle
            return
        }
        do {
            try CredentialStore.saveToken(token)
        } catch {
            if case CredentialStore.StoreError.keychain(let status) = error {
                qrError = "Couldn't save your sign-in (Keychain error \(status))."
            } else {
                qrError = "Couldn't save your sign-in. Try again."
            }
            qrPhase = .idle
            return
        }
        beginAuthenticatedSession(
            userID: claims.id,
            username: claims.username,
            avatar: claims.avatar
        )
        qrSession = nil
        qrPhase = .idle
        qrError = nil
        FavoritesManager.shared.reload()
    }

    private func beginAuthenticatedSession(
        userID: String,
        username: String,
        avatar: String?
    ) {
        sessionRevision &+= 1
        profileRefreshRevision &+= 1
        isRefreshingProfile = false
        profile = nil
        badges = []
        uploadLimits = nil
        profileError = nil
        isLoggedIn = true
        self.userID = userID
        self.username = username
        self.avatar = avatar
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let serviceError = error as? QRSignIn.ServiceError {
            return serviceError.errorDescription ?? "Something went wrong. Try again."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

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
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == ASWebAuthenticationSessionErrorDomain
            && nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
    }
    private static func activePresentationAnchor() -> ASPresentationAnchor? {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first
    }

    private static func makeVerifier() -> String {
        AuthenticationCodec.makeVerifier()
    }

    private static func makeChallenge(_ verifier: String) -> String {
        AuthenticationCodec.makeChallenge(verifier)
    }


    static func exchangedToken(from data: Data) -> String? {
        AuthenticationCodec.exchangedToken(from: data)
    }


    private static func parseJWT(_ jwt: String) -> (id: String, username: String, avatar: String?)? {
        AuthenticationCodec.claims(jwt)
    }
}
