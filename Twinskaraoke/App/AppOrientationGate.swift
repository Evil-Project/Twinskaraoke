import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Orientation opt-ins belong to the window displaying the video.
    @MainActor
    final class AppOrientationGate {
        static let shared = AppOrientationGate()
        private var owners: [ObjectIdentifier: Set<UUID>] = [:]

        /// The mask that applies when nothing holds a landscape lease.
        ///
        /// `application(_:supportedInterfaceOrientationsFor:)` overrides
        /// `UISupportedInterfaceOrientations`, so returning `.portrait` for
        /// every idiom quietly cancelled the four orientations the Info.plist
        /// declares for iPad — locking the entire iPad app to portrait outside
        /// the video player, sidebar shell included. iPhone stays portrait; it
        /// is the one that declares a narrow set and means it.
        private var baseOrientations: UIInterfaceOrientationMask {
            UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
        }

        func supportedOrientations(in scene: UIWindowScene?) -> UIInterfaceOrientationMask {
            guard let scene, owners[ObjectIdentifier(scene)]?.isEmpty == false else { return baseOrientations }
            // Union, not a replacement: a lease widens iPhone to landscape and
            // must never narrow iPad back out of upside-down.
            return baseOrientations.union(.allButUpsideDown)
        }

        func setLandscapeAllowed(_ allowed: Bool, owner: UUID, in scene: UIWindowScene) {
            let key = ObjectIdentifier(scene)
            if allowed { owners[key, default: []].insert(owner) }
            else { owners[key]?.remove(owner) }
            if owners[key]?.isEmpty == true { owners.removeValue(forKey: key) }
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if !allowed, owners[key] == nil {
                // Back to whatever this idiom allows, not unconditionally
                // portrait — on iPad that would yank the window upright on
                // leaving a video.
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: baseOrientations))
            }
        }
    }

    final class AppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _: UIApplication,
            handleEventsForBackgroundURLSession identifier: String,
            completionHandler: @escaping () -> Void
        ) {
            guard identifier == BackgroundDownloadTransport.identifier else { completionHandler(); return }
            let completion = BackgroundEventCompletion(completionHandler)
            DownloadManager.shared.handleBackgroundEvents {
                Task { @MainActor in completion.call() }
            }
        }

        func application(
            _: UIApplication,
            supportedInterfaceOrientationsFor window: UIWindow?
        ) -> UIInterfaceOrientationMask {
            AppOrientationGate.shared.supportedOrientations(in: window?.windowScene)
        }
    }

    @MainActor
    private final class BackgroundEventCompletion {
        private let completion: () -> Void
        init(_ completion: @escaping () -> Void) { self.completion = completion }
        func call() { completion() }
    }

    /// Resolves the actual hosting scene, including moves between windows.
    struct WindowSceneReader: UIViewRepresentable {
        var onChange: (UIWindowScene?) -> Void

        final class SceneView: UIView {
            var onChange: ((UIWindowScene?) -> Void)?
            override func didMoveToWindow() {
                super.didMoveToWindow()
                onChange?(window?.windowScene)
            }
        }
        func makeUIView(context: Context) -> SceneView {
            let view = SceneView()
            view.isUserInteractionEnabled = false
            view.onChange = onChange
            return view
        }
        func updateUIView(_ view: SceneView, context: Context) {
            view.onChange = onChange
        }
        static func dismantleUIView(_ view: SceneView, coordinator: ()) {
            view.onChange?(nil)
            view.onChange = nil
        }
    }

    private struct LandscapeOrientationModifier: ViewModifier {
        @State private var lease = LandscapeLease()
        func body(content: Content) -> some View {
            content
                .background(WindowSceneReader { lease.attach(to: $0) })
                .onAppear { lease.setVisible(true) }
                .onDisappear { lease.setVisible(false) }
        }
    }

    @MainActor
    private final class LandscapeLease {
        let id = UUID()
        weak var scene: UIWindowScene?
        var visible = false
        func attach(to newScene: UIWindowScene?) {
            guard scene !== newScene else { return }
            if let scene { AppOrientationGate.shared.setLandscapeAllowed(false, owner: id, in: scene) }
            scene = newScene
            if visible, let scene { AppOrientationGate.shared.setLandscapeAllowed(true, owner: id, in: scene) }
        }
        func setVisible(_ value: Bool) {
            visible = value
            if let scene { AppOrientationGate.shared.setLandscapeAllowed(value, owner: id, in: scene) }
        }
    }

    extension View {
        func allowsLandscapeOrientation() -> some View { modifier(LandscapeOrientationModifier()) }
    }
#else
    extension View {
        func allowsLandscapeOrientation() -> some View { self }
    }
#endif
