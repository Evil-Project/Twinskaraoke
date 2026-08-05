import Foundation
import Observation

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

    private enum Endpoint {
        static var login: String { "\(StorageHost.api)/api/auth/login" }
    }

    private enum AuthError: LocalizedError {
        case http(Int, String)
        case parse

        var errorDescription: String? {
            switch self {
            case .http(401, _): "Incorrect username or password."
            case .http(let code, _): "The server returned an error (\(code))."
            case .parse: "Couldn't read the server's response."
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

    func logout() {
        CredentialStore.deleteToken()
        isLoggedIn = false
        username = nil
        userID = nil
        avatar = nil
        errorMessage = nil
        FavoritesManager.shared.clear()
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
