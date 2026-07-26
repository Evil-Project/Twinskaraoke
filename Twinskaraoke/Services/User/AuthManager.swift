import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

@MainActor
private final class WebAuthenticationPresentationContextProvider:
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

@MainActor
final class AuthManager: NSObject, ObservableObject {
    @Published private(set) var isLoggedIn = false
    @Published private(set) var currentUsername: String?
    @Published private(set) var currentUserId: String?
    @Published private(set) var currentAvatar: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private(set) var authToken: String?
    private let defaults = UserDefaults.standard
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private var webAuthenticationContextProvider: WebAuthenticationPresentationContextProvider?

    private enum K {
        static let userId = "nk.userId"
        static let username = "nk.username"
        static let avatar = "nk.avatar"
        static let sessionCommitted = "nk.sessionCommitted"
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

    override init() {
        super.init()
        loadPersisted()
        NotificationCenter.default.addObserver(
            forName: .karaokeSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExpiredSession()
            }
        }
    }

    private func handleExpiredSession() {
        guard isLoggedIn else { return }
        logout()
        errorMessage = "Your session expired — please sign in again"
    }

    private func loadPersisted() {
        let token = CredentialStore.token
        let username = defaults.string(forKey: K.username)
        let commitMarker = defaults.object(forKey: K.sessionCommitted) as? Bool
        guard Self.persistedSessionIsComplete(
            token: token,
            username: username,
            commitMarker: commitMarker
        ), let token, let username
        else {
            if token != nil || username != nil || commitMarker != nil {
                clearPersistedSession()
            }
            return
        }
        if commitMarker == nil {
            defaults.set(true, forKey: K.sessionCommitted)
        }
        authToken = token
        currentUsername = username
        currentUserId = defaults.string(forKey: K.userId)
        currentAvatar = defaults.string(forKey: K.avatar)
        isLoggedIn = true
    }

    private func commit(token: String, userId: String, username: String, avatar: String?) throws {
        let previousUserID = defaults.string(forKey: K.userId)
        let previousCommitMarker = defaults.object(forKey: K.sessionCommitted)
        defaults.set(false, forKey: K.sessionCommitted)
        do {
            try CredentialStore.saveToken(token)
        } catch {
            if let previousCommitMarker {
                defaults.set(previousCommitMarker, forKey: K.sessionCommitted)
            } else {
                defaults.removeObject(forKey: K.sessionCommitted)
            }
            throw error
        }
        defaults.set(userId, forKey: K.userId)
        defaults.set(username, forKey: K.username)
        defaults.set(avatar, forKey: K.avatar)
        defaults.set(true, forKey: K.sessionCommitted)
        if previousUserID != userId {
            clearAccountScopedState()
        }
        authToken = token
        currentUserId = userId
        currentUsername = username
        currentAvatar = avatar
        isLoggedIn = true
        isLoading = false
        errorMessage = nil
    }

    func login(username: String, password: String) async {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            var req = URLRequest(url: URL(string: Endpoint.login)!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "username": username,
                "password": password,
            ])
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AuthError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, body)
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = json["token"] as? String
            else { throw AuthError.parse }
            let parsed = parseJwt(token)
            try commit(
                token: token,
                userId: parsed?.id ?? username,
                username: parsed?.username ?? username,
                avatar: parsed?.avatar
            )
        } catch {
            isLoading = false
            errorMessage = friendlyError(error)
        }
    }

    func loginWithDiscord() async {
        guard webAuthenticationSession == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            guard let presentationAnchor = activePresentationAnchor() else {
                throw AuthError.invalidCallback
            }
            let verifier = makeVerifier()
            let challenge = makeChallenge(verifier)
            let state = makeVerifier()
            var comps = URLComponents(string: Endpoint.discordAuth)!
            comps.queryItems = [
                .init(name: "client_id", value: Endpoint.discordClientId),
                .init(name: "redirect_uri", value: Endpoint.redirectUri),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: "identify"),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state),
            ]
            let callbackURL = try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: comps.url!,
                    callbackURLScheme: "neurokaraoke"
                ) { [weak self] url, error in
                    Task { @MainActor [weak self] in
                        self?.webAuthenticationSession = nil
                        self?.webAuthenticationContextProvider = nil
                    }
                    if let error {
                        cont.resume(throwing: Self.mappedWebAuthenticationError(error))
                        return
                    }
                    guard let url else {
                        cont.resume(throwing: AuthError.cancelled)
                        return
                    }
                    cont.resume(returning: url)
                }
                let contextProvider = WebAuthenticationPresentationContextProvider(
                    anchor: presentationAnchor
                )
                session.presentationContextProvider = contextProvider
                session.prefersEphemeralWebBrowserSession = true
                webAuthenticationContextProvider = contextProvider
                webAuthenticationSession = session
                guard session.start() else {
                    webAuthenticationSession = nil
                    webAuthenticationContextProvider = nil
                    cont.resume(throwing: AuthError.invalidCallback)
                    return
                }
            }
            guard
                let cbComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                cbComps.queryItems?.first(where: { $0.name == "state" })?.value == state,
                let code = cbComps.queryItems?.first(where: { $0.name == "code" })?.value
            else { throw AuthError.invalidCallback }
            let discordToken = try await exchangeDiscordCode(code, verifier: verifier)
            let nkToken = try await exchangeForNKToken(discordToken)
            let profile = try await fetchDiscordProfile(discordToken)
            try commit(
                token: nkToken,
                userId: profile.id,
                username: profile.username,
                avatar: profile.avatar
            )
        } catch {
            webAuthenticationSession = nil
            webAuthenticationContextProvider = nil
            isLoading = false
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
            let at = json["access_token"] as? String
        else { throw AuthError.parse }
        return at
    }

    private func exchangeForNKToken(_ discordToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: Endpoint.nkTokenExchange)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["accessToken": discordToken])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.http(
                (resp as? HTTPURLResponse)?.statusCode ?? 0,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        guard let token = Self.exchangedToken(from: data) else { throw AuthError.parse }
        return token
    }

    nonisolated static func exchangedToken(from data: Data) -> String? {
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            if let object = json as? [String: Any] {
                return validatedExchangedToken(
                    object["token"] as? String ?? object["accessToken"] as? String
                )
            }
            if let string = json as? String {
                return validatedExchangedToken(string)
            }
            return nil
        }
        return validatedExchangedToken(raw)
    }

    nonisolated static func mappedWebAuthenticationError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionErrorDomain,
           nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
        {
            return AuthError.cancelled
        }
        return error
    }

    private nonisolated static func validatedExchangedToken(_ candidate: String?) -> String? {
        guard let token = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              token.utf8.count <= 8_192
        else {
            return nil
        }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~+/=")
        )
        guard token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return token
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
        clearPersistedSession()
        clearAccountScopedState()
        authToken = nil
        currentUserId = nil
        currentUsername = nil
        currentAvatar = nil
        isLoggedIn = false
    }

    nonisolated static func persistedSessionIsComplete(
        token: String?,
        username: String?,
        commitMarker: Bool?
    ) -> Bool {
        guard let token, !token.isEmpty, let username, !username.isEmpty else { return false }
        return commitMarker != false
    }

    private func clearPersistedSession() {
        CredentialStore.deleteToken()
        [K.userId, K.username, K.avatar, K.sessionCommitted].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    private func clearAccountScopedState() {
        FavoritesManager.shared.clear()
        UserPlaylistsManager.shared.clear()
        Task { await KaraokeAPIClient.invalidateAccountScopedCaches() }
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

    private func activePresentationAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
            return window
        }
        guard let scene = scenes.first else { return nil }
        return ASPresentationAnchor(windowScene: scene)
    }

    enum AuthError: Error {
        case http(Int, String)
        case parse, invalidCallback, cancelled, notSignedIn
    }
}
