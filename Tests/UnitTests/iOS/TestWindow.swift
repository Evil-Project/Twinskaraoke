import UIKit

/// A window for layout tests, attached to the test host's scene.
///
/// `UIWindow(frame:)` is deprecated as of iOS 26: a window belongs to a scene.
/// Tests run inside the app, so its scene is already connected.
@MainActor
func makeTestWindow(frame: CGRect) -> UIWindow {
    guard let scene = UIApplication.shared.connectedScenes
        .lazy.compactMap({ $0 as? UIWindowScene }).first
    else {
        preconditionFailure("The test host has no connected window scene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = frame
    return window
}
