import Foundation

nonisolated enum GuestIdentity {
  private static let storageKey = "nk.guestId"

  static let current: String = {
    let defaults = UserDefaults.standard
    if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
      return existing
    }
    let generated = UUID().uuidString.lowercased()
    defaults.set(generated, forKey: storageKey)
    return generated
  }()

  static var isAuthenticated: Bool {
    CredentialStore.isAuthenticated
  }

  static func applyIfNeeded(to request: inout URLRequest) {
    guard !isAuthenticated else { return }
    request.setValue(current, forHTTPHeaderField: "x-guest-id")
  }
}
