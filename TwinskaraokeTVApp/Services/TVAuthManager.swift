import Foundation
import Observation

@MainActor
@Observable
final class TVAuthManager {
    private(set) var isLoggedIn = false
    private(set) var currentUsername: String?
    private(set) var currentUserId: String?
    private(set) var currentAvatar: String?
    private(set) var profile: UserProfile?
    private(set) var badges: [AccountBadge] = []
    private(set) var uploadLimits: UploadLimits?
    private(set) var isAuthenticating = false
    private(set) var isRefreshing = false
    private(set) var authError: String?
    private(set) var profileError: String?

    private(set) var qrSession: QRSignIn.Session?
    private(set) var qrPhase: QRPhase = .idle
    private(set) var qrError: String?

    enum QRPhase: Equatable {
        case idle
        case creating
        /// Code on screen, polling for a phone to approve it.
        case waiting
        /// Approved; exchanging the token for a session.
        case completing
        case expired
    }

    @ObservationIgnored private var qrTask: Task<Void, Never>?
    @ObservationIgnored private var sessionExpiredObserver: NSObjectProtocol?

    private let defaults = UserDefaults.standard

    private enum Key {
        static let userId = "nk.userId"
        static let username = "nk.username"
        static let avatar = "nk.avatar"
        static let sessionCommitted = "nk.sessionCommitted"
    }

    private struct LoginResponse: Decodable {
        let token: String
    }

    private enum AuthError: Error {
        case invalidResponse
        case httpStatus(Int)
    }

    init() {
        loadPersistedSession()
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: .karaokeSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.expireSession()
            }
        }
    }

    isolated deinit {
        qrTask?.cancel()
        if let sessionExpiredObserver {
            NotificationCenter.default.removeObserver(sessionExpiredObserver)
        }
    }

    var displayName: String {
        profile?.displayName ?? currentUsername ?? "Twinskaraoke listener"
    }

    var avatarURL: URL? {
        if let profileAvatar = profile?.avatarURL {
            return profileAvatar
        }
        guard let currentAvatar, !currentAvatar.isEmpty else { return nil }
        if let url = URL(string: currentAvatar), url.scheme != nil {
            return url
        }
        return URL(
            string: "\(StorageHost.base)\(ArtworkURLBuilder.normalizedPath(currentAvatar))"
        )
    }

    func login(username: String, password: String) async {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            authError = "Enter your username and password."
            return
        }

        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        do {
            guard let url = URL(string: "\(StorageHost.api)/api/auth/login") else {
                throw AuthError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: [
                    "username": trimmedUsername,
                    "password": password,
                ]
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw AuthError.httpStatus(httpResponse.statusCode)
            }

            let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
            let claims = Self.parseJWT(loginResponse.token)
            let previousUserId = defaults.string(forKey: Key.userId)
            try commitSession(
                token: loginResponse.token,
                userId: claims?.id ?? trimmedUsername,
                username: claims?.username ?? trimmedUsername,
                avatar: claims?.avatar
            )
            if previousUserId != nil, previousUserId != currentUserId {
                await KaraokeAPIClient.invalidateAccountScopedCaches()
            }
            await refreshAccount()
        } catch {
            authError = friendlyMessage(for: error)
        }
    }

    // MARK: - QR device pairing

    /// Requests a pairing code and polls until a signed-in phone approves it.
    /// Safe to call repeatedly; any in-flight attempt is replaced.
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
            qrError = friendlyMessage(for: error)
            qrPhase = .idle
            return
        }

        guard !Task.isCancelled else { return }
        qrSession = session
        qrPhase = .waiting

        let start = Date()
        // A single network blip shouldn't throw away a code the user is
        // already pointing a phone at; only give up after it keeps failing.
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
                // The server owns the deadline; the value from `createSession`
                // is only a placeholder until the first poll lands.
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
                    try await completeQRSignIn(token: token)
                    return
                }
            } catch {
                guard !Task.isCancelled, qrSession?.id == session.id else { return }
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    qrError = friendlyMessage(for: error)
                    qrPhase = .idle
                    return
                }
            }
        }
    }

    private func completeQRSignIn(token: String) async throws {
        // Without readable claims the session would persist with an empty
        // username, which `loadPersistedSession` treats as half-committed and
        // wipes on next launch — fail loudly here instead.
        guard let claims = Self.parseJWT(token) else {
            throw AuthError.invalidResponse
        }

        let previousUserId = defaults.string(forKey: Key.userId)
        try commitSession(
            token: token,
            userId: claims.id,
            username: claims.username,
            avatar: claims.avatar
        )
        if previousUserId != nil, previousUserId != currentUserId {
            await KaraokeAPIClient.invalidateAccountScopedCaches()
        }

        qrSession = nil
        qrPhase = .idle
        qrError = nil
        await refreshAccount()
    }

    func refreshAccount() async {
        guard isLoggedIn, let token = CredentialStore.token, !isRefreshing else { return }
        isRefreshing = true
        profileError = nil
        defer { isRefreshing = false }

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
                persistAvatar(response.profile.avatarUrl)
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
            profileError = "Some account details couldn’t be refreshed. Try again."
        }
    }

    func signOut() async {
        clearPersistedSession()
        clearAccountState()
        await KaraokeAPIClient.invalidateAccountScopedCaches()
    }

    func clearAuthError() {
        authError = nil
    }

    private func loadPersistedSession() {
        let token = CredentialStore.token
        let username = defaults.string(forKey: Key.username)
        let commitMarker = defaults.object(forKey: Key.sessionCommitted) as? Bool

        guard let token, !token.isEmpty,
              let username, !username.isEmpty,
              commitMarker != false
        else {
            if token != nil || username != nil || commitMarker != nil {
                clearPersistedSession()
            }
            return
        }

        if commitMarker == nil {
            defaults.set(true, forKey: Key.sessionCommitted)
        }
        currentUserId = defaults.string(forKey: Key.userId)
        currentUsername = username
        currentAvatar = defaults.string(forKey: Key.avatar)
        isLoggedIn = true
    }

    private func commitSession(
        token: String,
        userId: String,
        username: String,
        avatar: String?
    ) throws {
        let previousCommitMarker = defaults.object(forKey: Key.sessionCommitted)
        defaults.set(false, forKey: Key.sessionCommitted)
        do {
            try CredentialStore.saveToken(token)
        } catch {
            if let previousCommitMarker {
                defaults.set(previousCommitMarker, forKey: Key.sessionCommitted)
            } else {
                defaults.removeObject(forKey: Key.sessionCommitted)
            }
            throw error
        }

        defaults.set(userId, forKey: Key.userId)
        defaults.set(username, forKey: Key.username)
        if let avatar, !avatar.isEmpty {
            defaults.set(avatar, forKey: Key.avatar)
        } else {
            defaults.removeObject(forKey: Key.avatar)
        }
        defaults.set(true, forKey: Key.sessionCommitted)

        currentUserId = userId
        currentUsername = username
        currentAvatar = avatar
        isLoggedIn = true
        authError = nil
    }

    private func persistAvatar(_ avatar: String?) {
        guard let avatar, !avatar.isEmpty else { return }
        currentAvatar = avatar
        defaults.set(avatar, forKey: Key.avatar)
    }

    private func clearPersistedSession() {
        CredentialStore.deleteToken()
        [Key.userId, Key.username, Key.avatar, Key.sessionCommitted].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    private func clearAccountState() {
        // A pairing code outlives sign-out otherwise, and would sign the TV
        // straight back in the moment someone scanned it.
        cancelQRSignIn()
        currentUserId = nil
        currentUsername = nil
        currentAvatar = nil
        profile = nil
        badges = []
        uploadLimits = nil
        profileError = nil
        authError = nil
        isLoggedIn = false
    }

    private func expireSession() async {
        guard isLoggedIn else { return }
        await signOut()
        authError = "Your session expired. Sign in again."
    }

    private static func authorizedData(path: String) async throws -> Data {
        let request = try KaraokeAPIClient.request(path: path)
        return try await KaraokeAPIClient.data(for: request)
    }

    private static func parseJWT(_ token: String) -> (id: String, username: String, avatar: String?)? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let id = object[
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"
        ] as? String ?? ""
        let username = object[
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
        ] as? String ?? ""
        let avatar = (object["urn:discord:avatar"] as? String).flatMap {
            $0.isEmpty ? nil : $0
        }
        guard !id.isEmpty, !username.isEmpty else { return nil }
        return (id, username, avatar)
    }

    private func friendlyMessage(for error: Error) -> String {
        // `ServiceError` already phrases its own cases for this screen — most
        // usefully the 429 rate-limit text, which the generic fallback below
        // would otherwise flatten into a connection problem.
        if let serviceError = error as? QRSignIn.ServiceError,
           let description = serviceError.errorDescription
        {
            return description
        }
        if let authError = error as? AuthError {
            switch authError {
            case .httpStatus(401):
                return "That username or password isn’t correct."
            case let .httpStatus(statusCode):
                return "The server returned an error (\(statusCode)). Try again."
            case .invalidResponse:
                return "The server sent an unexpected response."
            }
        }
        if error is DecodingError {
            return "The server sent an unexpected response."
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "The request timed out. Check your connection and try again."
        }
        return "Couldn’t sign in. Check your connection and try again."
    }
}
