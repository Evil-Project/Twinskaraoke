import Observation
@testable import Twinskaraoke

@MainActor @Observable final class SplashTestSignals {
    var advanced = false
    var actions: [SplashWebsiteAction] = []
}
