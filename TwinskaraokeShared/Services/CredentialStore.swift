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
  private static let sessionCommittedKey = "nk.sessionCommitted"

  private static let tokenCacheLock = NSLock()
  private nonisolated(unsafe) static var cachedToken: String?

  static var token: String? {
    if UserDefaults.standard.object(forKey: sessionCommittedKey) as? Bool == false {
      return nil
    }
    tokenCacheLock.lock()
    let cached = cachedToken
    tokenCacheLock.unlock()
    if let cached {
      return cached
    }
    guard let resolved = resolveToken() else {
      return nil
    }
    tokenCacheLock.lock()
    cachedToken = resolved
    tokenCacheLock.unlock()
    return resolved
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
    tokenCacheLock.unlock()
  }

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: tokenAccount,
    ]
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
