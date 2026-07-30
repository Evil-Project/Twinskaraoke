import SwiftUI

struct ShimejiSettingsView: View {
    @ObservedObject private var resources = ShimejiResourceManager.shared
    @State private var spawnSettings = ShimejiSpawnSettings.load()
    @AppStorage("nk.shimeji.canClimb") private var canClimb: Bool = true

    var body: some View {
        List {
            statusSection
            if resources.manifest != nil {
                behaviorSection
            }
            if let manifest = resources.manifest {
                spawnCountSection
                charactersSection(manifest: manifest)
            }
        }
        .navigationTitle("Shimeji")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch resources.state {
            case .notDownloaded:
                Button("Download") {
                    AppHaptic.selection.play()
                    resources.download()
                }
                .foregroundStyle(Color.appAccent)
            case let .downloading(progress):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading Shimeji pack…")
                    ProgressView(value: progress)
                        .tint(.appAccent)
                }
                .padding(.vertical, 2)
            case .extracting:
                HStack {
                    Text("Setting up…")
                    Spacer()
                    ProgressView()
                }
            case .ready:
                if let manifest = resources.manifest {
                    Label("\(manifest.packName) ready — \(manifest.characters.count) characters", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.appAccent)
                }
            case let .failed(message):
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Try Again") {
                        AppHaptic.selection.play()
                        resources.retry()
                    }
                    .foregroundStyle(Color.appAccent)
                }
            }
        } header: {
            Text("Resource Pack")
        } footer: {
            Text("Shimeji characters and animations are downloaded separately from the app so new ones can be added later.")
        }

        if resources.manifest != nil {
            Section {
                Button("Remove Downloaded Pack", role: .destructive) {
                    AppHaptic.warning.play()
                    resources.deleteDownloadedPack()
                }
            }
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("Climbing", isOn: $canClimb)
                .tint(.appAccent)
        } header: {
            Text("Behavior")
        } footer: {
            Text("Climbing lets them scale the screen edges instead of just turning around.")
        }
    }

    private var spawnCountSection: some View {
        Section {
            Stepper(value: $spawnSettings.maxCount, in: 0 ... 8) {
                HStack {
                    Text("On Screen At Once")
                    Spacer()
                    Text("\(spawnSettings.maxCount)")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: spawnSettings.maxCount) { _, _ in
                persistAndRespawn()
            }
            Button("Respawn Now") {
                AppHaptic.selection.play()
                persistAndRespawn()
            }
            .foregroundStyle(Color.appAccent)
        } header: {
            Text("Population")
        } footer: {
            Text("Respawn clears everyone currently on screen and brings in a fresh set.")
        }
    }

    private func charactersSection(manifest: ShimejiManifest) -> some View {
        Section {
            HStack {
                Button("Use All") {
                    AppHaptic.selection.play()
                    spawnSettings.enabledCharacterIDs = Set(manifest.characters.map(\.id))
                    spawnSettings.hasCustomizedCharacters = true
                    persistAndRespawn()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Use None") {
                    AppHaptic.selection.play()
                    spawnSettings.enabledCharacterIDs = []
                    spawnSettings.hasCustomizedCharacters = true
                    persistAndRespawn()
                }
                .buttonStyle(.borderless)
            }
            .foregroundStyle(Color.appAccent)

            ForEach(manifest.characters) { character in
                Toggle(isOn: bindingFor(character)) {
                    Text(character.displayName)
                }
                .tint(.appAccent)
            }
        } header: {
            Text("Characters")
        } footer: {
            Text("Choose which characters can spawn. They walk, climb, sit on the tab bar, and can be dragged around the screen.")
        }
    }

    private func bindingFor(_ character: ShimejiCharacterDefinition) -> Binding<Bool> {
        Binding(
            get: { spawnSettings.enabledCharacterIDs.contains(character.id) },
            set: { isOn in
                if isOn {
                    spawnSettings.enabledCharacterIDs.insert(character.id)
                } else {
                    spawnSettings.enabledCharacterIDs.remove(character.id)
                }
                spawnSettings.hasCustomizedCharacters = true
                AppHaptic.selection.play()
                persistAndRespawn()
            }
        )
    }

    private func persistAndRespawn() {
        spawnSettings.save()
        if let manifest = resources.manifest {
            ShimejiEngine.shared.respawn(manifest: manifest)
        }
    }
}
