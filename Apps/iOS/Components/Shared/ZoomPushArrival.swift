import SwiftUI

private struct ZoomPushIsArrivingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while a zoom-pushed screen is still flying in.
    ///
    /// `ZoomPushDismissal` publishes it from the push's own transition
    /// coordinator; it is false everywhere else, including under reduce motion,
    /// where there is no zoom to wait for.
    ///
    /// Read it wherever a *single* tap commits something the user cannot easily
    /// undo — starting playback, most of all. The zoom does not gate input, so a
    /// tap aimed at the grid tile behind lands on the arriving screen, over
    /// whatever happens to sit at that Y coordinate. Scrolling and Back should
    /// stay live: they cost nothing if they were not meant.
    var zoomPushIsArriving: Bool {
        get { self[ZoomPushIsArrivingKey.self] }
        set { self[ZoomPushIsArrivingKey.self] = newValue }
    }
}
