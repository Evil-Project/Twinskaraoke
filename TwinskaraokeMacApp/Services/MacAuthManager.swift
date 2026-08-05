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

/// Username/password sign-in for the Mac app.
///
/// The tvOS target signs in by QR code because typing on a remote is painful;
/// a Mac has a keyboard, so this mirrors the iOS `AuthManager.login` flow
/// against the same `/api/auth/login` endpoint and the same Keychain-backed
/// `CredentialStore`. Discord OAuth is intentionally left out of this first
/// version — it needs an `ASWebAuthenticationSession` presentation anchor,
/// which is a separate piece of AppKit wiring.
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

    private enum AuthError: LocalizedError {
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
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Endpoint.callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor [weak self] in
                    self?.webAuthSession = nil
                    self?.webAuthContextProvider = nil
                }
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
        var request = URLRequest(url: URL(string: Endpoint.nkTokenExchange)!)
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
        CredentialStore.deleteToken()
        isLoggedIn = false
        username = nil
        userID = nil
        avatar = nil
        errorMessage = nil
        FavoritesManager.shared.clear()
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
