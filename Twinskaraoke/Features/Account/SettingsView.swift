import SwiftUI

struct SettingsView: View {
    @ObservedObject private var audioManager = AudioPlayerManager.shared
    @ObservedObject private var cacheManager = CacheManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("nk.addPlaylistSongsToLibrary") private var addPlaylistSongsToLibrary: Bool = false
    @AppStorage("nk.addFavoriteSongsToLibrary") private var addFavoriteSongsToLibrary: Bool = true
    @AppStorage("nk.syncLibrary") private var syncLibrary: Bool = true
    @AppStorage("nk.streamingQuality") private var streamingQuality: String = "high"
    @AppStorage("nk.downloadOnPlay") private var downloadOnPlay: Bool = false
    @AppStorage("nk.appearance") private var appearanceMode: String = AppearanceMode.dark.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @AppStorage("nk.experimentsEnabled") private var experimentsEnabled: Bool = false
    @AppStorage("nk.experimentalThemesEnabled") private var experimentalThemesEnabled: Bool = false
    @AppStorage("nk.experimentalShimejiEnabled") private var shimejiEnabled: Bool = false
    @State private var pendingAction: SettingsDestructiveAction?
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
            .alert(
                pendingAction?.title ?? "",
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                ),
                presenting: pendingAction
            ) { action in
                Button("Cancel", role: .cancel) {}
                    .tint(Color(uiColor: .systemBlue))
                Button(action.actionLabel, role: .destructive) {
                    perform(action)
                }
            } message: { action in
                Text(action.message)
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
            librarySection
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
            appearanceSection
            storageSection
            developerSection
            experimentsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }

    private var librarySection: some View {
        Section {
            Toggle("Add Playlist Songs", isOn: $addPlaylistSongsToLibrary)
                .tint(.appAccent)
            Toggle("Add Favorite Songs", isOn: $addFavoriteSongsToLibrary)
                .tint(.appAccent)
            Toggle("Sync Library", isOn: $syncLibrary)
                .tint(.appAccent)
        } header: {
            Text("Library")
        } footer: {
            Text("Add songs to your library when you add them to playlists or favorite them. Sync keeps library changes available across this app on your devices.")
        }
    }

    private var overviewSection: some View {
        Section {
            SettingsOverviewCard(
                title: audioManager.currentSong?.title ?? "Ready to Play",
                subtitle: audioManager.currentSong?.displayArtist ?? "Tune playback for Twinskaraoke",
                isPlaying: audioManager.isPlaying,
                badges: settingsBadges
            )
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
        .listSectionSpacing(8)
    }

    private var audioSection: some View {
        Section {
            Toggle("Auto Mix", isOn: $audioManager.autoMixEnabled)
                .tint(.appAccent)
            Toggle("Crossfade", isOn: $audioManager.crossfadeEnabled)
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
                "Autoplay Similar Songs",
                isOn: Binding(
                    get: { audioManager.autoplayEnabled },
                    set: { _ in audioManager.toggleAutoplay() }
                )
            )
            .tint(.appAccent)
            Picker("Audio Quality", selection: $streamingQuality) {
                Text("High Efficiency").tag("low")
                Text("High Quality").tag("medium")
                Text("Lossless").tag("high")
            }
        } header: {
            Text("Audio")
        } footer: {
            Text("Auto Mix blends compatible songs automatically. Crossfade uses the fixed duration you choose.")
        }
    }

    private var downloadsSection: some View {
        Section {
            Toggle("Auto-Download Played Songs", isOn: $downloadOnPlay)
                .tint(.appAccent)
        } header: {
            Text("Downloads")
        } footer: {
            Text("When enabled, songs you play are saved for offline listening.")
        }
    }

    private var lyricsSection: some View {
        Section {
            Toggle("Respect Reduce Motion", isOn: $respectReducedMotion)
                .tint(.appAccent)
        } header: {
            Text("Lyrics")
        } footer: {
            Text("Animated lyrics and transitions follow your motion preference.")
        }
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
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            Picker("Language", selection: $languageMode) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
        }
    }

    private var experimentsToggleBinding: Binding<Bool> {
        Binding(
            get: { experimentsEnabled },
            set: { newValue in
                if newValue {
                    showExperimentsAlert = true
                } else {
                    AppHaptic.light.play()
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
                newValue ? AppHaptic.success.play() : AppHaptic.light.play()
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
                newValue ? AppHaptic.success.play() : AppHaptic.light.play()
                if newValue {
                    if case .notDownloaded = ShimejiResourceManager.shared.state {
                        ShimejiResourceManager.shared.download()
                    }
                } else {
                    ShimejiResourceManager.shared.cancelDownload()
                }
            }
        )
    }

    @ViewBuilder
    private var developerSection: some View {
        if DeveloperMode.isEnabled {
            Section {
                NavigationLink {
                    DeveloperMenuView()
                } label: {
                    Text("Developer")
                }
            }
        }
    }

    private var settingsBadges: [SettingsOverviewBadge] {
        var badges: [SettingsOverviewBadge] = []
        if audioManager.crossfadeEnabled {
            badges.append(SettingsOverviewBadge(title: "\(Int(audioManager.crossfadeSeconds.rounded()))s Crossfade", symbol: "arrow.left.arrow.right"))
        }
        if audioManager.eqEnabled {
            badges.append(SettingsOverviewBadge(title: "EQ", symbol: "slider.vertical.3"))
        }
        if audioManager.karaokeMode {
            badges.append(SettingsOverviewBadge(title: "Vocal Removal", symbol: "music.mic"))
        } else if audioManager.bassEnhanceMode {
            badges.append(SettingsOverviewBadge(title: "Bass Enhance", symbol: "speaker.wave.3"))
        } else if audioManager.vocalEnhanceMode {
            badges.append(SettingsOverviewBadge(title: "Vocal Enhance", symbol: "music.mic.circle"))
        } else if audioManager.instrumentalEnhanceMode {
            badges.append(SettingsOverviewBadge(title: "Instrumental", symbol: "music.note"))
        }
        if downloadOnPlay {
            badges.append(SettingsOverviewBadge(title: "Auto Download", symbol: "arrow.down.circle"))
        }
        return badges.isEmpty ? [SettingsOverviewBadge(title: "Default", symbol: "checkmark.circle")] : badges
    }

    private var equalizerSection: some View {
        Section {
            Toggle("Equalizer", isOn: $audioManager.eqEnabled)
                .tint(.appAccent)
            if audioManager.eqEnabled {
                Picker("Preset", selection: $audioManager.eqPreset) {
                    ForEach(visibleEQPresets) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
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
            Text("10-band parametric EQ. Drag each band between -12 dB and +12 dB.")
        }
    }

    private var aiAudioSection: some View {
        Section {
            Toggle("AI Audio Processing", isOn: $audioManager.aiEnabled)
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
            .tint(.appAccent)
            .disabled(audioManager.isBackgroundKaraokeLocked)
            if audioManager.karaokeMode {
                HStack {
                    Text("Removal Level")
                    Spacer()
                    Text(aiStrengthLabel)
                        .foregroundStyle(.secondary)
                }
                StrengthSlider(
                    value: $audioManager.aiVocalStrength,
                    title: "Vocal Removal Level",
                    valueDescription: aiStrengthLabel
                )
            }
            Toggle("Bass Enhance", isOn: $audioManager.bassEnhanceMode)
                .tint(.appAccent)
                .disabled(audioManager.isBackgroundKaraokeLocked)
            if audioManager.bassEnhanceMode {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text(bassStrengthLabel)
                        .foregroundStyle(.secondary)
                }
                StrengthSlider(
                    value: $audioManager.bassEnhanceStrength,
                    title: "Bass Enhance Strength",
                    valueDescription: bassStrengthLabel
                )
            }
            Toggle("Vocal Enhance", isOn: $audioManager.vocalEnhanceMode)
                .tint(.appAccent)
                .disabled(audioManager.isBackgroundKaraokeLocked)
            if audioManager.vocalEnhanceMode {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text(vocalEnhanceStrengthLabel)
                        .foregroundStyle(.secondary)
                }
                StrengthSlider(
                    value: $audioManager.vocalEnhanceStrength,
                    title: "Vocal Enhance Strength",
                    valueDescription: vocalEnhanceStrengthLabel
                )
            }
            Toggle("Instrumental Enhance", isOn: $audioManager.instrumentalEnhanceMode)
                .tint(.appAccent)
                .disabled(audioManager.isBackgroundKaraokeLocked)
            if audioManager.instrumentalEnhanceMode {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text(instrumentalEnhanceStrengthLabel)
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
                    detail: "\(cacheManager.formattedLyricsCacheSize()) / 2 GB"
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
            Text("Storage")
        } footer: {
            Text(
                "Tap an indicator to clear that cache. Image cache is limited to 2 GB, music cache (including AI stems) to 4 GB, and lyrics cache to 2 GB. Items older than 6 months are automatically cleaned. Downloads are exempt from these limits."
            )
        }
    }

    private func request(_ action: SettingsDestructiveAction) {
        AppHaptic.warning.play()
        pendingAction = action
    }

    private func perform(_ action: SettingsDestructiveAction) {
        switch action {
        case .removeDownloads:
            DownloadManager.shared.removeAll()
        case .clearImageCache:
            cacheManager.clearImageCache()
        case .clearMusicCache:
            audioManager.clearCache()
            cacheManager.clearMusicCache()
        case .clearLyricsCache:
            cacheManager.clearLyricsCache()
        case .clearRecentlyPlayed:
            RecentlyPlayedStore.shared.reset()
        }
        AppHaptic.success.play()
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

private struct SettingsOverviewBadge: Hashable, Identifiable {
    let title: String
    let symbol: String

    var id: String {
        "\(symbol)-\(title)"
    }
}

private struct SettingsOverviewCard: View {
    let title: String
    let subtitle: String
    let isPlaying: Bool
    let badges: [SettingsOverviewBadge]
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.appControlActiveFill)
                    Image(systemName: isPlaying ? "waveform" : "music.note")
                        .font(.title2.bold())
                        .foregroundStyle(Color.appControlActiveForeground)
                        .scaleEffect(reduceMotion ? 1 : (isPlaying ? 1.06 : 1))
                        .opacity(isPlaying ? 1 : 0.88)
                        .animation(overviewAnimation, value: isPlaying)
                }
                .frame(width: 62, height: 62)
                .shadow(color: Color.appShadow, radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isPlaying ? "Now Playing" : "Playback")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(badges) { badge in
                        SettingsOverviewPill(badge: badge)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(16)
        .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isPlaying ? "Now playing" : "Playback settings"), \(title), \(subtitle)")
    }

    private var overviewAnimation: Animation? {
        reduceMotion ? nil : AppMotion.playful
    }
}

private struct SettingsOverviewPill: View {
    let badge: SettingsOverviewBadge

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: badge.symbol)
                .font(.caption.bold())
            Text(badge.title)
                .font(.caption.bold())
                .lineLimit(1)
        }
        .foregroundStyle(Color.appAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.appAccent.opacity(0.12), in: Capsule())
    }
}

private struct SettingsStorageActionRow: View {
    let symbol: String
    let title: String
    let detail: String
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
    var title: String = "Strength"
    var valueDescription: String?
    var step: Float = 0.05

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var lastFeedbackStep: Int?
    // In-drag value is local so per-frame drag updates don't publish through
    // the bound model; commits are throttled to ~10Hz for live audio feedback
    // and finalized on drag end.
    @State private var dragValue: Float?
    @State private var lastCommitUptime: TimeInterval = 0

    private var clampedValue: Float {
        min(1, max(0, dragValue ?? value))
    }

    private var percent: Int {
        Int((clampedValue * 100).rounded())
    }

    private var accessibilityValueText: String {
        if let valueDescription {
            return "\(valueDescription), \(percent) percent"
        }
        return "\(percent) percent"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(Color.appAccent)
                    .frame(width: max(8, geo.size.width * CGFloat(clampedValue)))
                    .animation(sliderAnimation, value: clampedValue)
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.appAccent.opacity(0.24), radius: 6, y: 2)
                    .offset(x: max(0, geo.size.width * CGFloat(clampedValue) - 9))
                    .animation(sliderAnimation, value: clampedValue)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let v = max(0, min(1, drag.location.x / max(1, geo.size.width)))
                        dragValue = Float(v)
                        playStepFeedback(for: Float(v))
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastCommitUptime >= 0.1 {
                            lastCommitUptime = now
                            commitValue(Float(v))
                        }
                    }
                    .onEnded { _ in
                        if let final = dragValue {
                            commitValue(final)
                        }
                        dragValue = nil
                        lastCommitUptime = 0
                        lastFeedbackStep = nil
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Swipe up or down to adjust.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setValue(clampedValue + step, feedback: true)
            case .decrement:
                setValue(clampedValue - step, feedback: true)
            @unknown default:
                break
            }
        }
    }

    private func setValue(_ newValue: Float, feedback: Bool) {
        let clamped = min(1, max(0, newValue))
        guard abs(clamped - value) > 0.001 else { return }
        value = clamped
        if feedback {
            playStepFeedback(for: clamped)
        }
    }

    private func commitValue(_ newValue: Float) {
        let clamped = min(1, max(0, newValue))
        guard abs(clamped - value) > 0.001 else { return }
        value = clamped
    }

    private func playStepFeedback(for value: Float) {
        let feedbackStep = Int((value * 20).rounded())
        guard feedbackStep != lastFeedbackStep else { return }
        lastFeedbackStep = feedbackStep
        AppHaptic.selection.play()
    }

    private var sliderAnimation: Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.82)
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
                        title: "\(frequencyAccessibilityLabel(Double(AVEnginePlayback.bandFrequencies[i]))) Equalizer"
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

    private func frequencyAccessibilityLabel(_ hz: Double) -> String {
        if hz >= 1000 {
            let k = hz / 1000
            if k.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(k)) kilohertz"
            }
            return String(format: "%.1f kilohertz", k)
        }
        return "\(Int(hz)) hertz"
    }
}

private struct EqualizerBand: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    var title: String

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var lastFeedbackStep: Int?
    // In-drag value is local so per-frame drag updates don't rewrite the whole
    // eqGainsDB array (UserDefaults + engine gains) every frame; commits are
    // throttled to ~10Hz for live audio feedback and finalized on drag end.
    @State private var dragValue: Float?
    @State private var lastCommitUptime: TimeInterval = 0

    private var clampedValue: Float {
        min(range.upperBound, max(range.lowerBound, dragValue ?? value))
    }

    private var valueText: String {
        if abs(clampedValue) < 0.05 {
            return "0 decibels"
        }
        return String(format: "%+.0f decibels", clampedValue)
    }

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let normalized = (clampedValue - range.lowerBound) / span
            let trackHeight = geo.size.height
            let knobY = trackHeight - CGFloat(normalized) * trackHeight
            let zeroY = trackHeight - CGFloat((0 - range.lowerBound) / span) * trackHeight
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)
                if clampedValue >= 0 {
                    Capsule()
                        .fill(Color.appAccent)
                        .frame(width: 4, height: max(0, zeroY - knobY))
                        .offset(y: knobY)
                } else {
                    Capsule()
                        .fill(Color.appAccent)
                        .frame(width: 4, height: max(0, knobY - zeroY))
                        .offset(y: zeroY)
                }
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.appAccent.opacity(0.24), radius: 6, y: 2)
                    .offset(y: knobY - 9)
            }
            .animation(bandAnimation, value: clampedValue)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let y = max(0, min(trackHeight, drag.location.y))
                        let n = 1 - (y / max(1, trackHeight))
                        let next = range.lowerBound + Float(n) * span
                        dragValue = next
                        playStepFeedback(for: next)
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastCommitUptime >= 0.1 {
                            lastCommitUptime = now
                            commitValue(next)
                        }
                    }
                    .onEnded { _ in
                        if let final = dragValue {
                            commitValue(final)
                        }
                        dragValue = nil
                        lastCommitUptime = 0
                        lastFeedbackStep = nil
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
        .accessibilityHint("Swipe up or down to adjust this band by one decibel.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setValue(clampedValue + 1, feedback: true)
            case .decrement:
                setValue(clampedValue - 1, feedback: true)
            @unknown default:
                break
            }
        }
    }

    private func setValue(_ newValue: Float, feedback: Bool) {
        let clamped = min(range.upperBound, max(range.lowerBound, newValue))
        guard abs(clamped - value) > 0.001 else { return }
        value = clamped
        if feedback {
            playStepFeedback(for: clamped)
        }
    }

    private func commitValue(_ newValue: Float) {
        let clamped = min(range.upperBound, max(range.lowerBound, newValue))
        guard abs(clamped - value) > 0.001 else { return }
        value = clamped
    }

    private func playStepFeedback(for value: Float) {
        let feedbackStep = Int(value.rounded())
        guard feedbackStep != lastFeedbackStep else { return }
        lastFeedbackStep = feedbackStep
        AppHaptic.selection.play()
    }

    private var bandAnimation: Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.82)
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
    private var displayLabel: String {
        let s = Int(seconds.rounded())
        return "\(s) Second\(s == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Duration")
                Spacer()
                Text(displayLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { seconds },
                    set: { seconds = $0.rounded() }
                ),
                in: range,
                step: 1
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
            .tint(.appAccent)
        }
        .padding(.vertical, 2)
    }
}

struct NotificationsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("nk.notifications.newSongs") private var notificationsNewSongs = true
    @AppStorage("nk.notifications.radio") private var notificationsRadio = true
    @AppStorage("nk.notifications.downloads") private var notificationsDownloads = true
    @AppStorage("nk.notifications.account") private var notificationsAccount = true

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
    }

    private var notificationsList: some View {
        List {
            Section {
                NotificationPreferenceToggle(
                    title: "New Songs",
                    isOn: $notificationsNewSongs
                )
                NotificationPreferenceToggle(
                    title: "Radio",
                    isOn: $notificationsRadio
                )
                NotificationPreferenceToggle(
                    title: "Downloads",
                    isOn: $notificationsDownloads
                )
                NotificationPreferenceToggle(
                    title: "Account",
                    isOn: $notificationsAccount
                )
            } footer: {
                Text("Preferences are saved on this device and use the same account settings style as Music.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
    }
}

private struct NotificationPreferenceToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .tint(.appAccent)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .onChange(of: isOn) { _, enabled in
            enabled ? AppHaptic.selection.play() : AppHaptic.light.play()
        }
    }
}
