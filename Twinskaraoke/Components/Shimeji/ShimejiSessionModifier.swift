import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Starts/stops the whole Shimeji system (overlay window + physics loop) in
/// response to the Experiments toggle and pack download state. Attach once,
/// at the app root.
struct ShimejiSessionModifier: ViewModifier {
    @AppStorage("nk.experimentsEnabled") private var experimentsEnabled: Bool = false
    @AppStorage("nk.experimentalShimejiEnabled") private var shimejiEnabled: Bool = false
    private let resources = ShimejiResourceManager.shared

    private var isActive: Bool {
        experimentsEnabled && shimejiEnabled && resources.state == .ready
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, active in
                updateSession(active: active)
            }
            .onChange(of: resources.manifest) { _, manifest in
                guard isActive, let manifest else { return }
                ShimejiEngine.shared.respawn(manifest: manifest)
            }
            .onAppear {
                updateSession(active: isActive)
            }
    }

    private func updateSession(active: Bool) {
        #if canImport(UIKit)
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
            else { return }

            if active, let manifest = resources.manifest {
                ShimejiOverlayController.shared.show(in: scene)
                ShimejiEngine.shared.start(manifest: manifest)
            } else {
                ShimejiEngine.shared.stop()
                ShimejiOverlayController.shared.hide()
            }
        #endif
    }
}

extension View {
    func shimejiSession() -> some View {
        modifier(ShimejiSessionModifier())
    }
}
