import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

@MainActor
final class AuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding
{
  @Published private(set) var isLoggedIn = false
  @Published private(set) var currentUsername: String?
  @Published private(set) var currentUserId: String?
  @Published private(set) var currentAvatar: String?
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?
  private(set) var authToken: String?
  private let defaults = UserDefaults.standard

  private enum K {
    static let token = "nk.token"
    static let userId = "nk.userId"
    static let username = "nk.username"
    static let avatar = "nk.avatar"
  }

  private enum Endpoint {
    static let login = "https://api.neurokaraoke.com/api/auth/login"
    static let discordAuth = "https://discord.com/oauth2/authorize"
    static let discordToken = "https://discord.com/api/oauth2/token"
    static let discordUser = "https://discord.com/api/users/@me"
    static let nkTokenExchange = "https://idk.neurokaraoke.com/api/auth/discord-token"
    static let discordClientId = "1447802634621943850"
    static let redirectUri = "neurokaraoke://auth"
  }
  override init() {
    super.init()
    loadPersisted()
  }
  private func loadPersisted() {
    guard
      let token = defaults.string(forKey: K.token),
      let username = defaults.string(forKey: K.username)
    else { return }
    authToken = token
    currentUsername = username
    currentUserId = defaults.string(forKey: K.userId)
    currentAvatar = defaults.string(forKey: K.avatar)
    isLoggedIn = true
  }
  private func commit(token: String, userId: String, username: String, avatar: String?) {
    defaults.set(token, forKey: K.token)
    defaults.set(userId, forKey: K.userId)
    defaults.set(username, forKey: K.username)
    defaults.set(avatar, forKey: K.avatar)
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
      commit(
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
    isLoading = true
    errorMessage = nil
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
      let callbackURL = try await withCheckedThrowingContinuation {
        (cont: CheckedContinuation<URL, Error>) in
        var didResume = false
        let resume: (Result<URL, Error>) -> Void = { result in
          guard !didResume else { return }
          didResume = true
          cont.resume(with: result)
        }
        let session = ASWebAuthenticationSession(
          url: comps.url!,
          callbackURLScheme: "neurokaraoke"
        ) { url, error in
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
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        session.start()
      }
      guard
        let cbComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
        let code = cbComps.queryItems?.first(where: { $0.name == "code" })?.value
      else { throw AuthError.invalidCallback }
      let discordToken = try await exchangeDiscordCode(code, verifier: verifier)
      let nkToken = try await exchangeForNKToken(discordToken)
      let profile = try await fetchDiscordProfile(discordToken)
      commit(
        token: nkToken ?? discordToken,
        userId: profile.id,
        username: profile.username,
        avatar: profile.avatar
      )
    } catch {
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
        String(data: data, encoding: .utf8) ?? "")
    }
    guard
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let at = json["access_token"] as? String
    else { throw AuthError.parse }
    return at
  }
  private func exchangeForNKToken(_ discordToken: String) async throws -> String? {
    var req = URLRequest(url: URL(string: Endpoint.nkTokenExchange)!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["accessToken": discordToken])
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
    let raw =
      String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if raw.hasPrefix("{"),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      return json["token"] as? String ?? json["accessToken"] as? String
    }
    return raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
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
  func logout() {
    [K.token, K.userId, K.username, K.avatar].forEach { defaults.removeObject(forKey: $0) }
    authToken = nil
    currentUserId = nil
    currentUsername = nil
    currentAvatar = nil
    isLoggedIn = false
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
      case .http(let c, _): return "Server error (\(c))"
      case .parse: return "Unexpected server response"
      case .invalidCallback: return "Authentication failed — try again"
      case .cancelled: return ""
      }
    }
    return error.localizedDescription
  }
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow } ?? ASPresentationAnchor()
  }

  enum AuthError: Error {
    case http(Int, String)
    case parse, invalidCallback, cancelled
  }
}
