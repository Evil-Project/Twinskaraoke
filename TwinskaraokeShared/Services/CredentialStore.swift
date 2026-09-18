import Foundation
import Security

nonisolated enum CredentialStore {
  enum StoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
      "Couldn't securely save your sign-in. Please try again."
    }
  }

  private static let service = "org.evilneuro.Twinskaraoke.credentials"
  private static let tokenAccount = "nk.token"
  private static let legacyTokenKey = "nk.token"

  private static let tokenCacheLock = NSLock()
  private nonisolated(unsafe) static var cachedToken: String?
  private nonisolated(unsafe) static var tokenCacheValid = false
  private nonisolated(unsafe) static var cacheGeneration: UInt64 = 0

  // Purely a Keychain wrapper: the half-committed-session marker
  // (nk.sessionCommitted) is enforced by AuthManager.persistedSessionIsComplete.
  enum TokenReadResult: Equatable {
    case available(String)
    case missing
    case unavailable(OSStatus)

    var token: String? {
      if case let .available(token) = self { return token }
      return nil
    }
  }

  static var token: String? { readToken().token }

  static func readToken() -> TokenReadResult {
    tokenCacheLock.lock()
    if tokenCacheValid {
      let result = cachedToken.map(TokenReadResult.available) ?? .missing
      tokenCacheLock.unlock()
      return result
    }
    let generation = cacheGeneration
    tokenCacheLock.unlock()
    let resolved = resolveToken()
    tokenCacheLock.lock()
    defer { tokenCacheLock.unlock() }
    if cacheGeneration != generation {
      return tokenCacheValid ? (cachedToken.map(TokenReadResult.available) ?? .missing) : resolved
    }
    if case .unavailable = resolved { return resolved }
    cachedToken = resolved.token
    tokenCacheValid = true
    return resolved
  }

  private static func resolveToken() -> TokenReadResult {
    let result = readTokenFromKeychain()
    guard case .missing = result else { return result }
    guard let legacy = UserDefaults.standard.string(forKey: legacyTokenKey), !legacy.isEmpty else {
      return .missing
    }
    do {
      try saveToken(legacy)
      return .available(legacy)
    } catch StoreError.keychain(let status) {
      return .unavailable(status)
    } catch {
      return .unavailable(errSecNotAvailable)
    }
  }

  /// A locked Keychain must not turn an authenticated request into an anonymous one.
  static func requestToken() throws -> String? {
    switch readToken() {
    case .available(let token): return token
    case .missing: return nil
    case .unavailable(let status): throw StoreError.keychain(status)
    }
  }

  static var isAuthenticated: Bool {
    guard let token else { return false }
    return !token.isEmpty
  }

  static func saveToken(_ token: String) throws {
    guard !token.isEmpty, let data = token.data(using: .utf8) else {
      throw StoreError.keychain(errSecParam)
    }

    let query = baseQuery
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess {
      UserDefaults.standard.removeObject(forKey: legacyTokenKey)
      setCachedToken(token)
      return
    }
    guard updateStatus == errSecItemNotFound else {
      throw StoreError.keychain(updateStatus)
    }

    var insert = query
    attributes.forEach { insert[$0.key] = $0.value }
    let insertStatus = SecItemAdd(insert as CFDictionary, nil)
    guard insertStatus == errSecSuccess else {
      throw StoreError.keychain(insertStatus)
    }
    UserDefaults.standard.removeObject(forKey: legacyTokenKey)
    setCachedToken(token)
  }

  static func deleteToken() {
    SecItemDelete(baseQuery as CFDictionary)
    UserDefaults.standard.removeObject(forKey: legacyTokenKey)
    setCachedToken(nil)
  }

  private static func setCachedToken(_ token: String?) {
    tokenCacheLock.lock()
    cachedToken = token
    tokenCacheValid = true
    cacheGeneration &+= 1
    tokenCacheLock.unlock()
  }

  private static var baseQuery: [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: tokenAccount,
    ]
    #if os(macOS)
      // macOS defaults SecItem to the legacy file-based keychain, which ignores
      // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly and can prompt on
      // access. Prefer the data-protection keychain so the Mac app behaves like
      // the iOS one — but only when this build can actually use it. Must be set
      // identically on every query for the same item, which is why it lives
      // here rather than at the call sites.
      if usesDataProtectionKeychain {
        query[kSecUseDataProtectionKeychain as String] = true
      }
    #endif
    return query
  }

  #if os(macOS)
    /// The macOS data-protection keychain requires an `application-identifier`
    /// or `keychain-access-groups` entitlement, which only a properly
    /// team-signed build carries. Ad-hoc and unsigned local builds have
    /// neither, and every SecItem call there fails with
    /// `errSecMissingEntitlement (-34018)` — which reads to the user as
    /// "couldn't save your sign-in".
    ///
    /// Probing once beats assuming: a shipping signed build gets the modern
    /// keychain, and a developer's local build silently falls back to the
    /// legacy one instead of being unable to sign in at all. Resolved a single
    /// time per process so save, read and delete can never disagree about which
    /// keychain holds the item.
    /// Only an entitlement-shaped failure counts as "this build cannot use the
    /// data-protection keychain". Statuses like `errSecInteractionNotAllowed`
    /// (keychain locked) or `errSecAuthFailed` are transient: treating those as
    /// a negative would make this launch read the legacy keychain only, hide a
    /// token a previous launch wrote to the data-protection one, sign the user
    /// out, and then write a second divergent token on the next save.
    private static let usesDataProtectionKeychain: Bool = {
      var probe: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: probeAccount,
        kSecValueData as String: Data("probe".utf8),
        kSecUseDataProtectionKeychain as String: true,
      ]
      let status = SecItemAdd(probe as CFDictionary, nil)
      if status == errSecSuccess || status == errSecDuplicateItem {
        probe.removeValue(forKey: kSecValueData as String)
        SecItemDelete(probe as CFDictionary)
        return true
      }
      // errSecMissingEntitlement: ad-hoc/unsigned build with no
      // application-identifier. errSecNotAvailable: no keychain available to
      // this process at all. Anything else, keep the modern keychain.
      return !(status == errSecMissingEntitlement || status == errSecNotAvailable)
    }()

    private static let probeAccount = "nk.keychainProbe"
  #endif

  private static func readTokenFromKeychain() -> TokenReadResult {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    DebugLogger.log("Keychain cold read OSStatus=\(status)", category: .network)
    return classifyRead(status: status, data: result as? Data)
  }

  static func classifyRead(status: OSStatus, data: Data?) -> TokenReadResult {
    if status == errSecItemNotFound { return .missing }
    guard status == errSecSuccess else { return .unavailable(status) }
    guard let data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
      return .unavailable(errSecDecode)
    }
    return .available(token)
  }
}
