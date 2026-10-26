import Foundation

extension DeveloperMode {
    static var splashTestingKind: SplashKind? {
        guard isEnabled else { return nil }
        return UserDefaults.standard.string(forKey: splashTestingKey).flatMap(SplashKind.init(rawValue:))
    }

}
