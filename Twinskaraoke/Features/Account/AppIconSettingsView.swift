import SwiftUI

struct AppIconSettingsView: View {
    @Bindable private var manager = AppIconManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        InsetGroupedList {
            Section {
                ForEach(AppIconChoice.allCases) { choice in
                    Button {
                        Task { await manager.select(choice) }
                    } label: {
                        HStack(spacing: 16) {
                            HStack(spacing: 8) {
                                iconPreview(choice, dark: false)
                                iconPreview(choice, dark: true)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(choice.title))
                                    .foregroundStyle(.primary)
                                Text(choice == .production ? "Default app icon" : "Try the experimental app icon")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if manager.selected == choice {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isChanging || !manager.isSupported)
                    .accessibilityIdentifier("AppIcon.\(choice.rawValue)")
                    .accessibilityAddTraits(manager.selected == choice ? [.isSelected] : [])
                    .accessibilityHint("Changes the iPhone and iPad app icon")
                }
                if manager.isChanging {
                    HStack {
                        ProgressView()
                        Text("Changing app icon…")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Previews show the light and dark versions. Your system appearance controls which version is used. Apple Watch keeps its installed icon because watchOS does not support alternate app icons.")
            }
            if !manager.isSupported {
                Section {
                    Text("Changing app icons is unavailable on this device.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { manager.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { manager.refresh() }
        }
        .alert("Could Not Change App Icon", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.clearError() } }
        )) {
            Button("OK", role: .cancel) { manager.clearError() }
        } message: {
            Text(manager.errorMessage ?? "Please try again.")
        }
    }

    private func iconPreview(_ choice: AppIconChoice, dark: Bool) -> some View {
        VStack(spacing: 4) {
            Image(choice.previewName(dark: dark))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(dark ? "Dark" : "Light")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

}
