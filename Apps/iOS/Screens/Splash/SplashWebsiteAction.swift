import Foundation

/// Native deferral is deliberately distinct from the website's terminal callbacks.
nonisolated enum SplashWebsiteAction: String {
    case completed, canceled, closed, deferred
}
