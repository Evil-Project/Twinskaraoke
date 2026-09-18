import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Each root owns an engine and attaches its overlay to its actual scene.
    struct ShimejiSessionModifier: ViewModifier {
        @AppStorage("nk.experimentsEnabled") private var experimentsEnabled = false
        @AppStorage("nk.experimentalShimejiEnabled") private var shimejiEnabled = false
        @Environment(\.scenePhase) private var scenePhase
        @State private var session = SceneSession()
        private let resources = ShimejiResourceManager.shared

        private var isActive: Bool {
            experimentsEnabled && shimejiEnabled && resources.state == .ready && scenePhase == .active
        }

        func body(content: Content) -> some View {
            content
                .environment(session.overlay.engine)
                .background(WindowSceneReader { scene in
                    session.attach(to: scene)
                    updateSession()
                })
                .onChange(of: isActive) { _, _ in updateSession() }
                .onChange(of: resources.manifest) { _, manifest in
                    if isActive, let manifest { session.overlay.engine.respawn(manifest: manifest) }
                    updateSession()
                }
                .onAppear { session.visible = true; updateSession() }
                .onDisappear { session.visible = false; session.overlay.hide() }
        }

        private func updateSession() {
            if isActive, session.visible, let scene = session.scene, let manifest = resources.manifest {
                session.overlay.show(in: scene)
                session.overlay.engine.start(manifest: manifest)
            } else {
                session.overlay.hide()
            }
        }

        @MainActor
        private final class SceneSession {
            let overlay = ShimejiOverlayController()
            weak var scene: UIWindowScene?
            var visible = false
            func attach(to value: UIWindowScene?) {
                guard scene !== value else { return }
                overlay.hide()
                scene = value
            }
        }
    }
#endif

extension View {
    @ViewBuilder
    func shimejiSession() -> some View {
        #if canImport(UIKit)
            modifier(ShimejiSessionModifier())
        #else
            self
        #endif
    }
}
