import Foundation

enum DeveloperMode {
    private static let key = "nk.developerMode"
    private static let easterEggKey = "nk.easterEggAlwaysTrigger"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static let splashTestingKey = "nk.developerSplashTesting"
    static var splashTestingKind: SplashKind? {
        guard isEnabled else { return nil }
        return UserDefaults.standard.string(forKey: splashTestingKey).flatMap(SplashKind.init(rawValue:))
    }

    static var easterEggAlwaysTrigger: Bool {
        get { UserDefaults.standard.bool(forKey: easterEggKey) }
        set { UserDefaults.standard.set(newValue, forKey: easterEggKey) }
    }

    static func shouldTriggerEasterEgg() -> Bool {
        if isEnabled, easterEggAlwaysTrigger { return true }
        return Int.random(in: 1 ... 1000) == 1
    }
}
