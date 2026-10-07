import SwiftUI
import Darwin

struct DeveloperMenuView: View {
    @AppStorage("nk.debugLogging") private var debugLogging: Bool = false
    @AppStorage("nk.easterEggAlwaysTrigger") private var easterEggAlwaysTrigger: Bool = false
    @AppStorage(DeveloperMode.splashTestingKey) private var splashTesting = "off"
    @State private var showDisableConfirm = false
    @State private var splashReset: SplashKind?
    @State private var splashResetError: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if DeveloperMode.isEnabled {
                Section("Walkthroughs") {
                    NavigationLink("Splash Screen Studio") { SplashStudioView() }
                    Picker("Always Show Splash", selection: $splashTesting) {
                        Text("Off").tag("off")
                        Text("Install").tag("install")
                        Text("Update").tag("update")
                    }
                    .accessibilityIdentifier("Developer.SplashTesting")
                    Button("Reset Install Splash & Close App", role: .destructive) { splashReset = .install }
                        .accessibilityIdentifier("Developer.ResetInstallSplash")
                    Button("Reset Update Splash & Close App", role: .destructive) { splashReset = .update }
                        .accessibilityIdentifier("Developer.ResetUpdateSplash")
                    Text("Reset clears only the selected splash history, turns Always Show Splash off, and closes the app. Reopen to test normal eligibility; login and other app data are preserved. Update reset affects the currently bundled announcement only.").font(.caption)
                    Text("Shows the selected walkthrough on each foreground opening. Uses separate test progress and leaves real completion history unchanged. Update testing also shows disabled announcements.")
                        .font(.caption)
                }
            }
            Section("Easter Eggs") {
                Toggle("Always Trigger", isOn: $easterEggAlwaysTrigger)
                    .tint(.appAccent)
            }
            Section("Logging") {
                Toggle("Debug Logging", isOn: $debugLogging)
                    .tint(.appAccent)
                if debugLogging {
                    Button("Export Debug Logs") {
                        exportDebugLogs()
                    }
                    .foregroundStyle(Color.appAccent)
                    Button("Clear Debug Logs") {
                        DebugLogger.clearLogs()
                    }
                    .foregroundStyle(Color.appAccent)
                }
            }
            Section {
                Button("Disable Developer Mode", role: .destructive) {
                    showDisableConfirm = true
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset \(splashReset?.rawValue.capitalized ?? "") Splash & Close App?", isPresented: Binding(get: { splashReset != nil }, set: { if !$0 { splashReset = nil } }), titleVisibility: .visible) {
            if let kind = splashReset {
                Button("Reset & Close App", role: .destructive) {
                    do {
                        try SplashCoordinator.shared.resetHistory(kind)
                        splashTesting = "off"
                        UserDefaults.standard.synchronize()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { exit(0) }
                    } catch { splashResetError = error.localizedDescription }
                }
            }
        } message: {
            Text("Your login and other app data stay intact. Disabled or nonmatching update announcements still will not appear.")
        }
        .alert("Splash reset failed", isPresented: Binding(get: { splashResetError != nil }, set: { if !$0 { splashResetError = nil } })) {
            Button("OK", role: .cancel) { splashResetError = nil }
        } message: { Text(splashResetError ?? "") }
        .alert("Disable developer mode?", isPresented: $showDisableConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Disable Developer Mode", role: .destructive) {
                debugLogging = false
                easterEggAlwaysTrigger = false
                splashTesting = "off"
                DeveloperMode.isEnabled = false
                dismiss()
            }
        } message: {
            Text("The developer menu and related features will be hidden until you turn developer mode back on.")
        }
    }

    private func exportDebugLogs() {
        #if canImport(UIKit)
            let logs = DebugLogger.exportLogs()
            let av = UIActivityViewController(
                activityItems: [logs], applicationActivities: nil
            )
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                let root = windowScene.keyWindow?.rootViewController
            {
                var presenter = root
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                // UIActivityViewController is a popover on iPad and crashes
                // without a source view/rect.
                if let popover = av.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(
                        x: presenter.view.bounds.midX,
                        y: presenter.view.bounds.midY,
                        width: 0,
                        height: 0
                    )
                    popover.permittedArrowDirections = []
                }
                presenter.present(av, animated: true)
            }
        #endif
    }
}
