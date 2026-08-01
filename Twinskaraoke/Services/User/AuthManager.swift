import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

@MainActor
final class AuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    enum AuthenticationMethod: Equatable {
        case password
        case discord
    }

    typealias SessionStateResetter = @MainActor () -> Void
    typealias PasswordTokenLoader = @MainActor @Sendable (_ username: String, _ password: String) async throws -> String

    private struct WebAuthenticationSessionHandle {
        let id: UUID
        let session: ASWebAuthenticationSession
        let cancelContinuation: @MainActor () -> Void
    }

    static let shared = AuthManager()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var currentUsername: String?
    @Published private(set) var currentUserId: String?
    @Published private(set) var currentAvatar: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeAuthenticationMethod: AuthenticationMethod?
    private(set) var authToken: String?
    private let defaults: UserDefaults
    private let sessionStateResetter: SessionStateResetter
    private let passwordTokenLoader: PasswordTokenLoader
    private var authenticationGeneration: UInt64 = 0
    private var webAuthenticationSession: WebAuthenticationSessionHandle?

    private enum K {
        static let token = "nk.token"
        static let userId = "nk.userId"
        static let username = "nk.username"
        static let avatar = "nk.avatar"
    }

    private enum Endpoint {
        static var login: String {
            "\(StorageHost.api)/api/auth/login"
        }

        static let discordAuth = "https://discord.com/oauth2/authorize"
        static let discordToken = "https://discord.com/api/oauth2/token"
        static let discordUser = "https://discord.com/api/users/@me"
        static var nkTokenExchange: String {
            "\(StorageHost.idk)/api/auth/discord-token"
        }

        static let discordClientId = "1447802634621943850"
        static let redirectUri = "neurokaraoke://auth"
    }

    override convenience init() {
        self.init(
            defaults: .standard,
            sessionStateResetter: {
                FavoritesManager.shared.clear()
                UserPlaylistsManager.shared.clear()
            }
        )
    }

    init(
        defaults: UserDefaults,
        sessionStateResetter: @escaping SessionStateResetter,
        passwordTokenLoader: PasswordTokenLoader? = nil
    ) {
        self.defaults = defaults
        self.sessionStateResetter = sessionStateResetter
        self.passwordTokenLoader = passwordTokenLoader ?? AuthManager.requestPasswordToken
        super.init()
        loadPersisted()
    }

    private func loadPersisted() {
        guard
            let persistedToken = defaults.string(forKey: K.token),
            let token = Self.normalizedToken(persistedToken),
            let username = defaults.string(forKey: K.username),
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            clearPersistedCredentials()
            return
        }
        if token != persistedToken {
            defaults.set(token, forKey: K.token)
        }
        authToken = token
        currentUsername = username
        currentUserId = defaults.string(forKey: K.userId)
        currentAvatar = defaults.string(forKey: K.avatar)
        isLoggedIn = true
    }

    private func commit(token: String, userId: String, username: String, avatar: String?) throws {
        guard let token = Self.normalizedToken(token) else { throw AuthError.parse }
        defaults.set(token, forKey: K.token)
        defaults.set(userId, forKey: K.userId)
        defaults.set(username, forKey: K.username)
        defaults.set(avatar, forKey: K.avatar)
        sessionStateResetter()
        authToken = token
        currentUserId = userId
        currentUsername = username
        currentAvatar = avatar
        isLoggedIn = true
        isLoading = false
        activeAuthenticationMethod = nil
        errorMessage = nil
    }

    func login(username: String, password: String) async {
        guard !Task.isCancelled else { return }
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        let authenticationGeneration = beginAuthenticationAttempt(method: .password)
        do {
            let loadedToken = try await passwordTokenLoader(username, password)
            guard canApplyAuthenticationResult(authenticationGeneration) else { return }
            guard let token = Self.normalizedToken(loadedToken) else { throw AuthError.parse }
            let parsed = parseJwt(token)
            try commit(
                token: token,
                userId: parsed?.id ?? username,
                username: parsed?.username ?? username,
                avatar: parsed?.avatar
            )
        } catch {
            guard canApplyAuthenticationResult(authenticationGeneration) else { return }
            isLoading = false
            activeAuthenticationMethod = nil
            errorMessage = friendlyError(error)
        }
    }

    func loginWithDiscord() async {
        guard !Task.isCancelled else { return }
        let authenticationGeneration = beginAuthenticationAttempt(method: .discord)
        do {
            let verifier = makeVerifier()
            let challenge = makeChallenge(verifier)
            var comps = URLComponents(string: Endpoint.discordAuth)!
            comps.queryItems = [
                .init(name: "client_id", value: Endpoint.discordClientId),
                .init(name: "redirect_uri", value: Endpoint.redirectUri),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: "identify"),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
            ]
            guard let authenticationURL = comps.url else { throw AuthError.invalidCallback }
            let callbackURL = try await requestDiscordCallbackURL(authenticationURL: authenticationURL)
            guard canApplyAuthenticationResult(authenticationGeneration) else { return }
            guard
                let cbComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                let code = cbComps.queryItems?.first(where: { $0.name == "code" })?.value
            else { throw AuthError.invalidCallback }
            let discordToken = try await exchangeDiscordCode(code, verifier: verifier)
            guard canApplyAuthenticationResult(authenticationGeneration) else { return }
            let nkToken = try await exchangeForNKToken(discordToken)
            guard canApplyAuthenticationResult(authenticationGeneration) else { return }
            let profile = try await fetchDiscordProfile(discordToken)
            guard canApplyAuthenticationResult(authenticationGeneration) else { return }
            try commit(
                token: nkToken,
                userId: profile.id,
                username: profile.username,
                avatar: profile.avatar
            )
        } catch {
            guard canApplyAuthenticationResult(authenticationGeneration) else { return }
            isLoading = false
            activeAuthenticationMethod = nil
            if case AuthError.cancelled = error { return }
            errorMessage = friendlyError(error)
        }
    }

    private func exchangeDiscordCode(_ code: String, verifier: String) async throws -> String {
        var req = URLRequest(url: URL(string: Endpoint.discordToken)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded =
            Endpoint.redirectUri
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Endpoint.redirectUri
        req.httpBody =
            "client_id=\(Endpoint.discordClientId)&grant_type=authorization_code&code=\(code)&redirect_uri=\(encoded)&code_verifier=\(verifier)"
                .data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.http(
                (resp as? HTTPURLResponse)?.statusCode ?? 0,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let at = json["access_token"] as? String,
            !at.isEmpty
        else { throw AuthError.parse }
        return at
    }

    private func exchangeForNKToken(_ discordToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: Endpoint.nkTokenExchange)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["accessToken": discordToken])
        let (data, resp) = try await URLSession.shared.data(for: req)
        return try Self.parseNKTokenExchangeResponse(
            data: data,
            statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0
        )
    }

    static func parseNKTokenExchangeResponse(data: Data, statusCode: Int) throws -> String {
        let responseBody = String(data: data, encoding: .utf8) ?? ""
        guard (200 ..< 300).contains(statusCode) else {
            throw AuthError.http(statusCode, responseBody)
        }

        let raw = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw AuthError.parse }

        let token: String
        if raw.hasPrefix("{") {
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let value = json["token"] as? String ?? json["accessToken"] as? String
            else { throw AuthError.parse }
            token = value
        } else if raw.hasPrefix("\"") {
            guard let value = try? JSONDecoder().decode(String.self, from: Data(raw.utf8)) else {
                throw AuthError.parse
            }
            token = value
        } else if raw.hasPrefix("[") {
            throw AuthError.parse
        } else {
            token = raw
        }

        guard let normalizedToken = Self.normalizedToken(token) else { throw AuthError.parse }
        return normalizedToken
    }

    static func exchangedToken(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let value = json["token"] as? String ?? json["accessToken"] as? String
            return value.flatMap(normalizedToken)
        }
        if let value = try? JSONDecoder().decode(String.self, from: data) {
            return normalizedToken(value)
        }
        return nil
    }

    static func mappedWebAuthenticationError(_ error: Error) -> Error {
        if let sessionError = error as? ASWebAuthenticationSessionError,
           sessionError.code == .canceledLogin
        {
            return AuthError.cancelled
        }
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionErrorDomain,
           nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
        {
            return AuthError.cancelled
        }
        return error
    }

    static func persistedSessionIsComplete(
        token: String?,
        username: String?,
        commitMarker: Bool?
    ) -> Bool {
        guard commitMarker != false,
              let token,
              normalizedToken(token) != nil,
              let username,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return true
    }

    private struct DiscordProfile {
        let id, username: String
        let avatar: String?
    }

    private func fetchDiscordProfile(_ token: String) async throws -> DiscordProfile {
        var req = URLRequest(url: URL(string: Endpoint.discordUser)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.parse
        }
        let id = json["id"] as? String ?? ""
        let username = json["global_name"] as? String ?? json["username"] as? String ?? ""
        let avatarId = json["avatar"] as? String
        let avatar = avatarId.map { "https://cdn.discordapp.com/avatars/\(id)/\($0).png" }
        return DiscordProfile(id: id, username: username, avatar: avatar)
    }

    private func parseJwt(_ jwt: String) -> (id: String, username: String, avatar: String?)? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        b64 = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard
            let data = Data(base64Encoded: b64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let id =
            json["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"] as? String ?? ""
        let name = json["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"] as? String ?? ""
        let av = (json["urn:discord:avatar"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard !id.isEmpty, !name.isEmpty else { return nil }
        return (id, name, av)
    }

    func approveQRSession(sessionId: String) async throws {
        guard let token = authToken, isLoggedIn else { throw AuthError.notSignedIn }
        var req = URLRequest(url: URL(string: "\(StorageHost.api)/api/auth/approve-qr")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["sessionId": sessionId])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AuthError.http(
                (resp as? HTTPURLResponse)?.statusCode ?? 0,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    func logout() {
        cancelAuthentication()
        clearPersistedCredentials()
        sessionStateResetter()
        authToken = nil
        currentUserId = nil
        currentUsername = nil
        currentAvatar = nil
        isLoggedIn = false
        isLoading = false
        activeAuthenticationMethod = nil
        errorMessage = nil
    }

    func cancelAuthentication() {
        authenticationGeneration &+= 1
        cancelWebAuthenticationSession()
        isLoading = false
        activeAuthenticationMethod = nil
        errorMessage = nil
    }

    private func beginAuthenticationAttempt(method: AuthenticationMethod) -> UInt64 {
        authenticationGeneration &+= 1
        cancelWebAuthenticationSession()
        isLoading = true
        activeAuthenticationMethod = method
        errorMessage = nil
        return authenticationGeneration
    }

    private func canApplyAuthenticationResult(_ generation: UInt64) -> Bool {
        guard generation == authenticationGeneration else { return false }
        guard !Task.isCancelled else {
            isLoading = false
            activeAuthenticationMethod = nil
            errorMessage = nil
            return false
        }
        return true
    }

    private func requestDiscordCallbackURL(authenticationURL: URL) async throws -> URL {
        let sessionID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                var didResume = false
                let resume: @MainActor (Result<URL, Error>) -> Void = { [weak self] result in
                    guard !didResume else { return }
                    didResume = true
                    if self?.webAuthenticationSession?.id == sessionID {
                        self?.webAuthenticationSession = nil
                    }
                    continuation.resume(with: result)
                }

                let session = ASWebAuthenticationSession(
                    url: authenticationURL,
                    callbackURLScheme: "neurokaraoke"
                ) { url, error in
                    Task { @MainActor in
                        if let sessionError = error as? ASWebAuthenticationSessionError,
                           sessionError.code == .canceledLogin
                        {
                            resume(.failure(AuthError.cancelled))
                            return
                        }
                        if let error {
                            resume(.failure(error))
                            return
                        }
                        guard let url else {
                            resume(.failure(AuthError.cancelled))
                            return
                        }
                        resume(.success(url))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                webAuthenticationSession = WebAuthenticationSessionHandle(
                    id: sessionID,
                    session: session,
                    cancelContinuation: {
                        resume(.failure(AuthError.cancelled))
                    }
                )
                guard session.start() else {
                    resume(.failure(AuthError.invalidCallback))
                    return
                }
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.cancelWebAuthenticationSession(matching: sessionID)
            }
        }
    }

    private func cancelWebAuthenticationSession(matching sessionID: UUID? = nil) {
        guard let activeSession = webAuthenticationSession else { return }
        if let sessionID, activeSession.id != sessionID { return }
        webAuthenticationSession = nil
        activeSession.cancelContinuation()
        activeSession.session.cancel()
    }

    private func clearPersistedCredentials() {
        [K.token, K.userId, K.username, K.avatar].forEach { defaults.removeObject(forKey: $0) }
    }

    static func persistedDescriptor(defaults: UserDefaults = .standard) -> WatchSessionLink.Descriptor {
        guard
            let persistedToken = defaults.string(forKey: K.token),
            normalizedToken(persistedToken) != nil,
            let username = defaults.string(forKey: K.username),
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .signedOut
        }

        return WatchSessionLink.Descriptor(
            isSignedIn: true,
            userID: defaults.string(forKey: K.userId),
            username: username,
            avatar: defaults.string(forKey: K.avatar),
            generation: 0
        )
    }

    private static func requestPasswordToken(username: String, password: String) async throws -> String {
        var request = URLRequest(url: URL(string: Endpoint.login)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.http((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawToken = json["token"] as? String,
            let token = Self.normalizedToken(rawToken)
        else { throw AuthError.parse }
        return token
    }

    private static func normalizedToken(_ token: String) -> String? {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedToken.isEmpty ? nil : normalizedToken
    }

    private func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeChallenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func friendlyError(_ error: Error) -> String {
        if let e = error as? AuthError {
            switch e {
            case .http(401, _): return "Invalid username or password"
            case let .http(c, _): return "Server error (\(c))"
            case .parse: return "Unexpected server response"
            case .invalidCallback: return "Authentication failed — try again"
            case .cancelled: return ""
            case .notSignedIn: return "You need to sign in first"
            }
        }
        return error.localizedDescription
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
            return window
        }
        guard let scene = scenes.first else {
            // Auth UI is only requested while a scene is connected.
            preconditionFailure("presentationAnchor requested with no connected window scene")
        }
        return ASPresentationAnchor(windowScene: scene)
    }

    enum AuthError: Error, Equatable {
        case http(Int, String)
        case parse, invalidCallback, cancelled, notSignedIn
    }
}
