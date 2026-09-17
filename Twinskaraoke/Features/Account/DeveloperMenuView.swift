import SwiftUI

struct DeveloperMenuView: View {
    @AppStorage("nk.debugLogging") private var debugLogging: Bool = false
    @AppStorage("nk.easterEggAlwaysTrigger") private var easterEggAlwaysTrigger: Bool = false
    @AppStorage(TabRevealStrategy.storageKey)
    private var tabRevealStrategyRaw: Int = TabRevealStrategy.automatic.rawValue
    @AppStorage(TabRevealProbe.storageKey) private var tabRevealDiagnostics: Bool = false
    @State private var showDisableConfirm = false
    @State private var showIsolatedProbe = false

    /// The picker stores a choice; this is what the app actually installs. They
    /// differ for `automatic`, and the difference is worth showing — a stale
    /// selection reading as the shipping default cost a device round trip.
    private var resolvedRevealStrategy: TabRevealStrategy {
        (TabRevealStrategy(rawValue: tabRevealStrategyRaw) ?? .automatic).resolved
    }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("Easter Eggs") {
                Toggle("Always Trigger", isOn: $easterEggAlwaysTrigger)
                    .tint(.appAccent)
            }
            Section {
                Picker("Reveal", selection: $tabRevealStrategyRaw) {
                    ForEach(TabRevealStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy.rawValue)
                    }
                }
                .pickerStyle(.inline)
                LabeledContent("In force", value: resolvedRevealStrategy.title)
                Toggle("Reveal Diagnostics", isOn: $tabRevealDiagnostics)
                    .tint(.appAccent)
                Button("Isolated Tab Bar") {
                    showIsolatedProbe = true
                }
                .foregroundStyle(Color.appAccent)
            } header: {
                Text("Tab Bar Reveal")
            } footer: {
                Text("Scrolling up a short distance reveals the minimized tab bar. These pick who performs that reveal, for comparing the animation on a device. Diagnostics record the tab bar and accessory layers frame by frame into the debug log; turn Debug Logging on as well, reproduce once, then export. Isolated Tab Bar runs the selected strategy against a bare tab bar and accessory, with none of this app's player, gestures or bridges around it.")
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
        .fullScreenCover(isPresented: $showIsolatedProbe) {
            IsolatedTabRevealProbe { showIsolatedProbe = false }
        }
        .alert("Disable developer mode?", isPresented: $showDisableConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Disable Developer Mode", role: .destructive) {
                debugLogging = false
                easterEggAlwaysTrigger = false
                tabRevealDiagnostics = false
                tabRevealStrategyRaw = TabRevealStrategy.automatic.rawValue
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
