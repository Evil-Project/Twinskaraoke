import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Decides whether the app may currently rotate out of portrait.
    ///
    /// Every screen in the app is laid out for portrait except the video player,
    /// which goes full-screen when the device is tilted. Declaring landscape in
    /// the Info.plist is what makes rotation possible at all, but on its own it
    /// would let *every* portrait-designed screen rotate too. So landscape is
    /// declared as supported and then gated here: only screens that explicitly
    /// opt in are allowed to turn.
    ///
    /// Opt-ins are counted rather than stored as a flag, because video screens
    /// can overlap — pushing a video from the "Similar Videos" list leaves the
    /// previous screen alive underneath until the transition settles, and a
    /// plain Boolean would let the disappearing screen switch landscape back off
    /// for the one that just appeared.
    @MainActor
    final class AppOrientationGate {
        static let shared = AppOrientationGate()

        private var landscapeOptInCount = 0

        private init() {}

        var supportedOrientations: UIInterfaceOrientationMask {
            landscapeOptInCount > 0 ? .allButUpsideDown : .portrait
        }

        func beginAllowingLandscape() {
            landscapeOptInCount += 1
            notifySystemOfChange()
        }

        func endAllowingLandscape() {
            landscapeOptInCount = max(0, landscapeOptInCount - 1)
            notifySystemOfChange()
            if landscapeOptInCount == 0 {
                returnToPortrait()
            }
        }

        /// Asks UIKit to re-read `supportedInterfaceOrientationsFor:`, which it
        /// otherwise only consults when a view controller is presented.
        private func notifySystemOfChange() {
            rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        /// Rotates back to portrait when the last opt-in goes away.
        ///
        /// Clearing the gate alone is not enough: if the device is physically
        /// held in landscape when the video screen is dismissed, UIKit has no
        /// reason to rotate until the user moves the device, leaving a portrait
        /// layout stranded sideways.
        private func returnToPortrait() {
            guard let windowScene else { return }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }

        private var windowScene: UIWindowScene? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        }

        private var rootViewController: UIViewController? {
            windowScene?.keyWindow?.rootViewController
        }
    }

    final class AppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _: UIApplication,
            supportedInterfaceOrientationsFor _: UIWindow?
        ) -> UIInterfaceOrientationMask {
            AppOrientationGate.shared.supportedOrientations
        }
    }

    extension View {
        /// Lets this screen rotate into landscape while it is on screen.
        func allowsLandscapeOrientation() -> some View {
            modifier(LandscapeOrientationModifier())
        }
    }

    private struct LandscapeOrientationModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .onAppear { AppOrientationGate.shared.beginAllowingLandscape() }
                .onDisappear { AppOrientationGate.shared.endAllowingLandscape() }
        }
    }
#else
    extension View {
        func allowsLandscapeOrientation() -> some View { self }
    }
#endif
