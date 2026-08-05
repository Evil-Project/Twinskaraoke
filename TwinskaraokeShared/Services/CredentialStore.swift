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
  static var token: String? {
    tokenCacheLock.lock()
    if tokenCacheValid {
      let cached = cachedToken
      tokenCacheLock.unlock()
      return cached
    }
    let generation = cacheGeneration
    tokenCacheLock.unlock()
    let resolved = resolveToken()
    tokenCacheLock.lock()
    if cacheGeneration == generation {
      cachedToken = resolved
      tokenCacheValid = true
      tokenCacheLock.unlock()
      return resolved
    }
    // A save/delete raced the cold read: the resolved value may be a revoked
    // token, so hand out the current cached value (nil if it was cleared).
    let current = tokenCacheValid ? cachedToken : nil
    tokenCacheLock.unlock()
    return current
  }

  private static func resolveToken() -> String? {
    if let stored = readTokenFromKeychain() {
      return stored
    }

    guard let legacy = UserDefaults.standard.string(forKey: legacyTokenKey), !legacy.isEmpty else {
      return nil
    }

    do {
      try saveToken(legacy)
      return legacy
    } catch {
      UserDefaults.standard.removeObject(forKey: legacyTokenKey)
      return nil
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
      // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly and prompts the user
      // on access. Opt into the data-protection keychain so the Mac app behaves
      // like the iOS one. Must be set identically on every query for the same
      // item, which is why it lives here rather than at the call sites.
      query[kSecUseDataProtectionKeychain as String] = true
    #endif
    return query
  }

  private static func readTokenFromKeychain() -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data,
          let token = String(data: data, encoding: .utf8),
          !token.isEmpty
    else {
      return nil
    }
    return token
  }
}
