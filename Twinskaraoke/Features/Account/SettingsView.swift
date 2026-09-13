import SwiftUI

struct SettingsView: View {
    @Bindable private var audioManager = AudioPlayerManager.shared
    private let cacheManager = CacheManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("nk.downloadOnPlay") private var downloadOnPlay: Bool = false
    @AppStorage("nk.appearance") private var appearanceMode: String = AppearanceMode.dark.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @AppStorage(AppHaptics.storageKey) private var hapticsEnabled: Bool = true
    @AppStorage(AppHaptics.strengthStorageKey) private var hapticStrength: String = AppHapticStrength.default.rawValue
    @AppStorage("nk.experimentsEnabled") private var experimentsEnabled: Bool = false
    @AppStorage("nk.experimentalThemesEnabled") private var experimentalThemesEnabled: Bool = false
    @AppStorage("nk.experimentalShimejiEnabled") private var shimejiEnabled: Bool = false
    @AppStorage("nk.developerMode") private var developerModeEnabled = false
    @State private var pendingAction: SettingsDestructiveAction?
    @State private var isClearingStorage = false
    @State private var showStorageError = false
    @State private var showAutoAnalyzeAlert = false
    @State private var showExperimentsAlert = false
    private var visibleEQPresets: [EQPreset] {
        EQPreset.allCases.filter { preset in
            preset != .custom || audioManager.eqPreset == .custom
        }
    }

    private var usesWideOverview: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        settingsContent
            .navigationTitle("Music")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Could Not Clear Storage", isPresented: $showStorageError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Some files could not be removed. Please try again.")
            }
            .alert(
                Text(LocalizedStringKey(pendingAction?.title ?? "")),
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                ),
                presenting: pendingAction
            ) { action in
                Button("Cancel", role: .cancel) {}
                    .tint(Color(uiColor: .systemBlue))
                Button(LocalizedStringKey(action.actionLabel), role: .destructive) {
                    perform(action)
                }
            } message: { action in
                Text(LocalizedStringKey(action.message))
            }
            .alert(
                "Turn on auto-analyze during playback?",
                isPresented: $showAutoAnalyzeAlert
            ) {
                Button("Turn On") {
                    AppHaptic.success.play()
                    audioManager.aiAutoAnalyze = true
                }
                Button("Cancel", role: .cancel) {
                    AppHaptic.selection.play()
                }
            } message: {
                Text(
                    "Songs will be analyzed in the background so audio effects can switch instantly during playback.\n\nThis uses more battery and processing power. Separated stems count toward the 4 GB music cache limit."
                )
            }
            .alert(
                "Turn On Experiments?",
                isPresented: $showExperimentsAlert
            ) {
                Button("Enable", role: .destructive) {
                    AppHaptic.success.play()
                    experimentsEnabled = true
                }
                Button("Cancel", role: .cancel) {
                    AppHaptic.selection.play()
                }
            } message: {
                Text(
                    "Experiments are early, unfinished features. They may be unstable, change without notice, or be removed in a future update."
                )
            }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if usesWideOverview {
            ZStack(alignment: .top) {
                ScreenBackgroundFill(style: .grouped)
                settingsList
                    .frame(maxWidth: 700, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .accessibilityIdentifier("Settings.WideOverview")
            }
        } else {
            settingsList
        }
    }

    private var settingsList: some View {
        List {
            audioSection
            downloadsSection
            if DeviceCapability.supportsKaraoke {
                aiAudioSection
                if audioManager.aiEnabled {
                    karaokeSection
                }
            }
            equalizerSection
            lyricsSection
            hapticsSection
            appearanceSection
            storageSection
            developerSection
            experimentsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }

    private var audioSection: some View {
        Section {
            Toggle("Auto Mix", isOn: $audioManager.autoMixEnabled)
            .toggleHaptic(audioManager.autoMixEnabled)
                .tint(.appAccent)
            Toggle("Crossfade", isOn: $audioManager.crossfadeEnabled)
            .toggleHaptic(audioManager.crossfadeEnabled)
                .tint(.appAccent)
            if audioManager.crossfadeEnabled {
                CrossfadeDurationRow(
                    seconds: Binding(
                        get: { audioManager.crossfadeSeconds },
                        set: { audioManager.crossfadeSeconds = $0 }
                    )
                )
            }
            Toggle(
                "Autoplay",
                isOn: Binding(
                    get: { audioManager.autoplayEnabled },
                    set: { audioManager.autoplayEnabled = $0 }
                )
            )
            .toggleHaptic(audioManager.autoplayEnabled)
            .tint(.appAccent)
        } header: {
            Text("Audio")
        } footer: {
            Text("Auto Mix blends compatible songs automatically. Crossfade uses the fixed duration you choose. Autoplay continues with account recommendations, or trending songs when recommendations are unavailable. These features do not apply to radio.")
        }
    }

    private var downloadsSection: some View {
        Section {
            Toggle("Auto-Download Played Songs", isOn: $downloadOnPlay)
            .toggleHaptic(downloadOnPlay)
                .onChange(of: downloadOnPlay) { _, enabled in
                    if enabled { audioManager.autoDownloadCurrentSongIfEnabled() }
                }
                .tint(.appAccent)
        } header: {
            Text("Downloads")
        } footer: {
            Text("When enabled, the current song and songs you play next are saved for offline listening. This may use cellular data. Turning this off leaves existing downloads and downloads already in progress intact.")
        }
    }

    private var lyricsSection: some View {
        Section {
            Toggle("Respect Reduce Motion", isOn: $respectReducedMotion)
            .toggleHaptic(respectReducedMotion)
                .tint(.appAccent)
        } header: {
            Text("Lyrics")
        } footer: {
            Text("Animated lyrics and transitions follow your motion preference.")
        }
    }

    private var hapticsSection: some View {
        Section {
            Toggle("Haptic Feedback", isOn: hapticsToggleBinding)
                .tint(.appAccent)
            if hapticsEnabled {
                Picker("Strength", selection: hapticStrengthBinding) {
                    ForEach(AppHapticStrength.allCases) { strength in
                        Text(LocalizedStringKey(strength.label)).tag(strength)
                    }
                }
                .accessibilityIdentifier("Settings.HapticStrength")
            }
        } header: {
            Text("Haptics")
        } footer: {
            Text(LocalizedStringKey(hapticsEnabled
                ? "Taps, swipes and controls answer back with a vibration. Strength sets how hard they land — each control keeps its own character at every level."
                : "Taps, swipes and controls answer back with a vibration."))
        }
    }

    /// Plays the chosen level as you pick it, so the setting is judged by feel
    /// rather than by the word next to it.
    private var hapticStrengthBinding: Binding<AppHapticStrength> {
        Binding(
            get: { AppHapticStrength(rawValue: hapticStrength) ?? .default },
            set: { newValue in
                hapticStrength = newValue.rawValue
                AppHaptic.commit.play()
            }
        )
    }

    /// Fires the confirmation *before* writing the preference when switching
    /// off, so the toggle's own haptic still plays — the user's last impression
    /// of the feature is the feature working, not silence.
    private var hapticsToggleBinding: Binding<Bool> {
        Binding(
            get: { hapticsEnabled },
            set: { newValue in
                if newValue {
                    hapticsEnabled = true
                    AppHaptic.success.play()
                } else {
                    AppHaptic.dismiss.play()
                    hapticsEnabled = false
                }
            }
        )
    }

    private var visibleAppearanceModes: [AppearanceMode] {
        AppearanceMode.allCases.filter { mode in
            !mode.isExperimental || experimentalThemesEnabled
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceMode) {
                ForEach(visibleAppearanceModes, id: \.rawValue) { mode in
                    Text(LocalizedStringKey("Theme." + mode.rawValue)).tag(mode.rawValue)
                }
            }
            .accessibilityIdentifier("Settings.Theme")
            .selectionHaptic(appearanceMode)
            Picker("Language", selection: $languageMode) {
                ForEach(AppLanguage.allCases) { language in
                    if language == .system {
                        Text("System").tag(language.rawValue)
                    } else {
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
            }
            .selectionHaptic(languageMode)
        }
    }

    private var experimentsToggleBinding: Binding<Bool> {
        Binding(
            get: { experimentsEnabled },
            set: { newValue in
                if newValue {
                    showExperimentsAlert = true
                } else {
                    AppHaptic.dismiss.play()
                    experimentsEnabled = false
                    experimentalThemesEnabled = false
                    shimejiEnabled = false
                    resetThemeIfHiddenByExperiments()
                }
            }
        )
    }

    private var experimentalThemesToggleBinding: Binding<Bool> {
        Binding(
            get: { experimentalThemesEnabled },
            set: { newValue in
                experimentalThemesEnabled = newValue
                newValue ? AppHaptic.success.play() : AppHaptic.dismiss.play()
                if !newValue {
                    resetThemeIfHiddenByExperiments()
                }
            }
        )
    }

    /// If Experimental Themes gets turned off while an experimental theme is
    /// active, fall back to Dark so the picker never holds a hidden value.
    private func resetThemeIfHiddenByExperiments() {
        if AppearanceMode(rawValue: appearanceMode)?.isExperimental == true {
            appearanceMode = AppearanceMode.dark.rawValue
        }
    }

    private var experimentsSection: some View {
        Section {
            Toggle("Enable Experiments", isOn: experimentsToggleBinding)
                .tint(.appAccent)
            if experimentsEnabled {
                Toggle("Experimental Themes", isOn: experimentalThemesToggleBinding)
                    .tint(.appAccent)
                Toggle("Shimeji", isOn: shimejiToggleBinding)
                    .tint(.appAccent)
                if shimejiEnabled {
                    NavigationLink {
                        ShimejiSettingsView()
                    } label: {
                        Text("Shimeji Characters")
                    }
                }
            }
        } header: {
            Text("Experiments")
        } footer: {
            if experimentsEnabled {
                Text("Experimental Themes adds early, in-progress themes to the theme picker above. Shimeji adds tiny animated characters that wander around on top of the app.")
            } else {
                Text("Turn on Experiments to access early, in-progress features before they're finished.")
            }
        }
    }

    private var shimejiToggleBinding: Binding<Bool> {
        Binding(
            get: { shimejiEnabled },
            set: { newValue in
                shimejiEnabled = newValue
                newValue ? AppHaptic.success.play() : AppHaptic.dismiss.play()
                // Turning the experiment on is an explicit ask for the
                // characters, so it overrides an earlier pack removal.
                if newValue {
                    ShimejiResourceManager.shared.download()
                }
            }
        )
    }

    @ViewBuilder
    private var developerSection: some View {
        if developerModeEnabled {
            Section {
                NavigationLink {
                    DeveloperMenuView()
                } label: {
                    Text("Developer")
                }
            }
        }
    }

    private var equalizerSection: some View {
        Section {
            Toggle("Equalizer", isOn: $audioManager.eqEnabled)
            .toggleHaptic(audioManager.eqEnabled)
                .tint(.appAccent)
            if audioManager.eqEnabled {
                Picker("Preset", selection: $audioManager.eqPreset) {
                    ForEach(visibleEQPresets) { preset in
                        Text(LocalizedStringKey(preset.rawValue)).tag(preset)
                    }
                }
                .selectionHaptic(audioManager.eqPreset)
                EqualizerBands(gainsDB: $audioManager.eqGainsDB)
                    .padding(.vertical, 8)
                Button("Reset Equalizer") {
                    audioManager.eqPreset = .flat
                }
                .foregroundStyle(Color.appAccent)
            }
        } header: {
            Text("Equalizer")
        } footer: {
            Text("10-band parametric EQ. Drag each band between -12 dB and +12 dB. Equalizer and AI audio effects apply to songs, not radio.")
        }
    }

    private var aiAudioSection: some View {
        Section {
            Toggle("AI Audio Processing", isOn: $audioManager.aiEnabled)
            .toggleHaptic(audioManager.aiEnabled)
                .tint(.appAccent)

            if audioManager.aiEnabled {
                Toggle("Auto-Analyze During Playback", isOn: Binding(
                    get: { audioManager.aiAutoAnalyze },
                    set: { newValue in
                        if newValue {
                            showAutoAnalyzeAlert = true
                        } else {
                            audioManager.aiAutoAnalyze = false
                        }
                    }
                ))
                .tint(.appAccent)
            }
        } header: {
            Text("AI Audio")
        } footer: {
            if audioManager.aiEnabled, !audioManager.aiAutoAnalyze {
                Text(
                    "Real-time mode: audio is processed on-the-fly when you activate an audio effect. Only the unplayed portion is processed for faster results."
                )
            } else if !audioManager.aiEnabled {
                Text(
                    "Enable AI Audio Processing to access vocal removal, bass enhance, and other AI-powered audio features."
                )
            } else {
                Text(
                    "Powered by on-device AI. Audio is separated into vocals and instrumentals using a neural network model."
                )
            }
        }
    }

    private var karaokeSection: some View {
        Section {
            Toggle(
                "Vocal Removal",
                isOn: Binding(
                    get: { audioManager.karaokeMode },
                    set: { audioManager.karaokeMode = $0 }
                )
            )
            .toggleHaptic(audioManager.karaokeMode)
            .tint(.appAccent)
            .disabled(audioManager.isBackgroundKaraokeLocked)
            if audioManager.karaokeMode {
                HStack {
                    Text("Removal Level")
                    Spacer()
                    Text(LocalizedStringKey(aiStrengthLabel))
                        .foregroundStyle(.secondary)
                }
                StrengthSlider(
                    value: $audioManager.aiVocalStrength,
                    title: "Vocal Removal Level",
                    valueDescription: aiStrengthLabel
                )
            }
            Toggle("Bass Enhance", isOn: $audioManager.bassEnhanceMode)
            .toggleHaptic(audioManager.bassEnhanceMode)
                .tint(.appAccent)
                .disabled(audioManager.isBackgroundKaraokeLocked)
            if audioManager.bassEnhanceMode {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text(LocalizedStringKey(bassStrengthLabel))
                        .foregroundStyle(.secondary)
                }
                StrengthSlider(
                    value: $audioManager.bassEnhanceStrength,
                    title: "Bass Enhance Strength",
                    valueDescription: bassStrengthLabel
                )
            }
            Toggle("Vocal Enhance", isOn: $audioManager.vocalEnhanceMode)
            .toggleHaptic(audioManager.vocalEnhanceMode)
                .tint(.appAccent)
                .disabled(audioManager.isBackgroundKaraokeLocked)
            if audioManager.vocalEnhanceMode {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text(LocalizedStringKey(vocalEnhanceStrengthLabel))
                        .foregroundStyle(.secondary)
                }
                StrengthSlider(
                    value: $audioManager.vocalEnhanceStrength,
                    title: "Vocal Enhance Strength",
                    valueDescription: vocalEnhanceStrengthLabel
                )
            }
            Toggle("Instrumental Enhance", isOn: $audioManager.instrumentalEnhanceMode)
            .toggleHaptic(audioManager.instrumentalEnhanceMode)
                .tint(.appAccent)
                .disabled(audioManager.isBackgroundKaraokeLocked)
            if audioManager.instrumentalEnhanceMode {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text(LocalizedStringKey(instrumentalEnhanceStrengthLabel))
                        .foregroundStyle(.secondary)
                }
                StrengthSlider(
                    value: $audioManager.instrumentalEnhanceStrength,
                    title: "Instrumental Enhance Strength",
                    valueDescription: instrumentalEnhanceStrengthLabel
                )
            }
            if audioManager.isBackgroundKaraokeLocked {
                Text("Available after background processing finishes for the current song.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Audio Effects")
        } footer: {
            Text(
                "Audio effects use on-device AI to separate vocals and instrumentals in real time. For best results, use headphones or external speakers."
            )
        }
    }

    private var storageSection: some View {
        Section {
            Button {
                request(.clearImageCache)
            } label: {
                SettingsStorageActionRow(
                    symbol: "photo",
                    title: "Image Cache",
                    detail: "\(cacheManager.formattedImageCacheSize()) / 2 GB"
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
            Button {
                request(.clearMusicCache)
            } label: {
                SettingsStorageActionRow(
                    symbol: "music.note",
                    title: "Music Cache",
                    detail: "\(cacheManager.formattedMusicCacheSize()) / 4 GB"
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
            Button {
                request(.clearLyricsCache)
            } label: {
                SettingsStorageActionRow(
                    symbol: "text.quote",
                    title: "Lyrics Cache",
                    detail: "\(cacheManager.formattedLyricsCacheSize()) / 64 MB"
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
            Button(role: .destructive) {
                request(.removeDownloads)
            } label: {
                SettingsStorageActionRow(
                    symbol: "arrow.down.circle",
                    title: "Remove All Downloads",
                    detail: "Offline songs on this device",
                    isDestructive: true
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
            Button(role: .destructive) {
                request(.clearRecentlyPlayed)
            } label: {
                SettingsStorageActionRow(
                    symbol: "clock.arrow.circlepath",
                    title: "Clear Recently Played",
                    detail: "Listening history on this device",
                    isDestructive: true
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
        } header: {
            HStack {
                Text("Storage")
                if isClearingStorage { ProgressView() }
            }
        } footer: {
            Text(
                "Tap an indicator to clear that cache. Image cache is limited to 2 GB, music cache (including AI stems) to 4 GB, and lyrics cache to 64 MB. Items older than 6 months are automatically cleaned. Downloads are exempt from these limits."
            )
        }
        .disabled(isClearingStorage)
    }

    private func request(_ action: SettingsDestructiveAction) {
        AppHaptic.selection.play()
        pendingAction = action
    }

    private func perform(_ action: SettingsDestructiveAction) {
        guard !isClearingStorage else { return }
        pendingAction = nil
        isClearingStorage = true
        switch action {
        case .removeDownloads:
            DownloadManager.shared.removeAll { success in finishStorageAction(success) }
        case .clearImageCache:
            cacheManager.clearImageCache { success in finishStorageAction(success) }
        case .clearMusicCache:
            audioManager.clearCache()
            cacheManager.clearMusicCache { success in finishStorageAction(success) }
        case .clearLyricsCache:
            cacheManager.clearLyricsCache { success in finishStorageAction(success) }
        case .clearRecentlyPlayed:
            RecentlyPlayedStore.shared.reset()
            finishStorageAction(true)
        }
    }

    private func finishStorageAction(_ success: Bool) {
        isClearingStorage = false
        if success {
            AppHaptic.success.play()
        } else {
            showStorageError = true
        }
    }

    private var aiStrengthLabel: String {
        let s = audioManager.aiVocalStrength
        if s >= 0.99 { return "Maximum" }
        if s >= 0.75 { return "Strong" }
        if s >= 0.45 { return "Medium" }
        if s >= 0.15 { return "Light" }
        return "Off"
    }

    private var bassStrengthLabel: String {
        strengthText(audioManager.bassEnhanceStrength)
    }

    private var vocalEnhanceStrengthLabel: String {
        strengthText(audioManager.vocalEnhanceStrength)
    }

    private var instrumentalEnhanceStrengthLabel: String {
        strengthText(audioManager.instrumentalEnhanceStrength)
    }

    private func strengthText(_ v: Float) -> String {
        if v < 0.15 { return "Almost off" }
        if v < 0.45 { return "Light" }
        if v < 0.75 { return "Medium" }
        if v < 0.95 { return "Strong" }
        return "Maximum"
    }
}

private struct SettingsStorageActionRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var isDestructive = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 36, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.appAccent : .primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

private struct StrengthSlider: View {
    @Binding var value: Float
    var title: LocalizedStringKey = "Strength"
    var valueDescription: String?

    var body: some View {
        NativeLevelSlider(value: Binding(get: { Double(value) }, set: { value = Float($0) }))
            .tint(.appAccent)
            .frame(minHeight: 44)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: Text {
        let percent = Int((min(1, max(0, value)) * 100).rounded())
        if let valueDescription {
            return Text("\(Text(LocalizedStringKey(valueDescription))), \(percent) percent")
        }
        return Text("\(percent) percent")
    }
}

private struct EqualizerBands: View {
    @Binding var gainsDB: [Float]
    private let range: ClosedRange<Float> = -12 ... 12
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0 ..< AVEnginePlayback.eqBandCount, id: \.self) { i in
                VStack(spacing: 6) {
                    Text(gainLabel(gainsDB.indices.contains(i) ? gainsDB[i] : 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(height: 12)
                        .monospacedDigit()
                    EqualizerBand(
                        value: bandBinding(i),
                        range: range,
                        title: "\(Int(AVEnginePlayback.bandFrequencies[i])) Hz Equalizer"
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    Text(frequencyLabel(Double(AVEnginePlayback.bandFrequencies[i])))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(height: 12)
                }
            }
        }
    }

    private func bandBinding(_ i: Int) -> Binding<Float> {
        Binding(
            get: { gainsDB.indices.contains(i) ? gainsDB[i] : 0 },
            set: { newValue in
                guard gainsDB.indices.contains(i) else { return }
                var copy = gainsDB
                copy[i] = min(range.upperBound, max(range.lowerBound, newValue))
                gainsDB = copy
            }
        )
    }

    private func gainLabel(_ db: Float) -> String {
        if abs(db) < 0.05 { return "0" }
        return String(format: "%+.0f", db)
    }

    private func frequencyLabel(_ hz: Double) -> String {
        if hz >= 1000 {
            let k = hz / 1000
            if k.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(k))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(Int(hz))"
    }
}

private struct EqualizerBand: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    var title: LocalizedStringKey

    var body: some View {
        GeometryReader { geometry in
            NativeLevelSlider(
                value: Binding(get: { Double(value) }, set: { value = Float($0) }),
                range: Double(range.lowerBound)...Double(range.upperBound),
                neutralValue: 0
            )
            .tint(.appAccent)
            .environment(\.layoutDirection, .leftToRight)
            .frame(width: geometry.size.height, height: geometry.size.width)
            .rotationEffect(.degrees(-90))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .accessibilityLabel(title)
            .accessibilityValue(Text("\(Int(value.rounded())) decibels"))
        }
    }
}

private enum SettingsDestructiveAction {
    case removeDownloads
    case clearImageCache
    case clearMusicCache
    case clearLyricsCache
    case clearRecentlyPlayed
    var title: String {
        switch self {
        case .removeDownloads: "Remove all downloads?"
        case .clearImageCache: "Clear image cache?"
        case .clearMusicCache: "Clear music cache?"
        case .clearLyricsCache: "Clear lyrics cache?"
        case .clearRecentlyPlayed: "Clear recently played history?"
        }
    }

    var message: String {
        switch self {
        case .removeDownloads:
            "All offline downloads on this device will be removed."
        case .clearImageCache:
            "Cached artwork and images will be removed. They will download again as you use the app."
        case .clearMusicCache:
            "Cached audio files and AI stems will be removed. Songs may buffer again the next time you play them."
        case .clearLyricsCache:
            "Cached lyrics and lyric translations will be removed."
        case .clearRecentlyPlayed:
            "Your recently played history will be removed from this device."
        }
    }

    var actionLabel: String {
        switch self {
        case .removeDownloads: "Remove All Downloads"
        case .clearImageCache: "Clear Image Cache"
        case .clearMusicCache: "Clear Music Cache"
        case .clearLyricsCache: "Clear Lyrics Cache"
        case .clearRecentlyPlayed: "Clear Recently Played"
        }
    }
}

private struct CrossfadeDurationRow: View {
    @Binding var seconds: Double
    private let range: ClosedRange<Double> = 1 ... 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Duration")
                Spacer()
                Text("\(Int(seconds.rounded())) s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { seconds },
                    set: { seconds = $0.rounded() }
                ),
                in: range
            ) {
                Text("Crossfade Duration")
            } minimumValueLabel: {
                Text("1s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("15s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .sliderThumbVisibility(.hidden)
            .tint(.appAccent)
        }
        .padding(.vertical, 2)
    }
}

struct NotificationsView: View {
    @Bindable private var notifications = DownloadNotifications.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                ZStack(alignment: .top) {
                    ScreenBackgroundFill(style: .grouped)
                    notificationsList
                        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, AM.Spacing.screenMargin)
                        .accessibilityIdentifier("Notifications.WideOverview")
                }
            } else {
                notificationsList
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await notifications.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await notifications.refreshAuthorization() } }
        }
        .alert("Could Not Enable Notifications", isPresented: $notifications.hasError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private var notificationsList: some View {
        List {
            Section {
                Toggle("Download Notifications", isOn: Binding(
                    get: { notifications.isEnabled },
                    set: { enabled in
                        Task { await notifications.setEnabled(enabled) }
                    }
                ))
                .disabled(notifications.isUpdating)
                .tint(.appAccent)
                if notifications.permissionDenied {
                    Button("Open Notification Settings") {
                        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            } footer: {
                Text(LocalizedStringKey(notifications.permissionDenied
                    ? "Notifications are disabled in system settings. Allow notifications there to receive download updates."
                    : "Notify when downloads finish while the app is in the background."))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }
}
