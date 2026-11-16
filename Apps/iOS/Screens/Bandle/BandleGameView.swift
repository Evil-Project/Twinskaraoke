import SwiftUI

struct BandleGameView: View {
    @State private var model = BandleGameViewModel()
    @State private var clipPlayer = BandleClipPlayer()

    var body: some View {
        ScrollView {
            VStack(spacing: AM.Spacing.l) {
                if BandleMode.visibleModes.count > 1 {
                    BandleSegmentPicker(
                        title: String(localized: "Challenge mode"),
                        options: BandleMode.visibleModes,
                        selection: model.mode,
                        isDisabled: model.phase.isBusy || model.phase == .playing,
                        optionTitle: \.title,
                        onSelect: selectMode
                    )
                    .accessibilityIdentifier("Bandle.ModePicker")
                }

                if model.phase == .ready || (model.phase == .completed && !model.isPractice) {
                    BandlePersonalSummary(userData: model.userData)
                }

                if let message = model.errorMessage {
                    BandleErrorBanner(message: message, onRetry: retry)
                }

                switch model.phase {
                case .idle, .loading:
                    ProgressView(String(localized: "Loading challenge..."))
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .accessibilityIdentifier("Bandle.Loading")
                case .ready:
                    if model.canStart {
                        BandleStartCard(isSignedIn: model.isSignedIn, onStart: start, onPractice: startPractice)
                    }
                case .starting, .playing, .submitting:
                    BandlePlayArea(
                        model: model,
                        clipPlayer: clipPlayer,
                        onSubmit: submitGuess,
                        onSkip: skip,
                        onSelectClip: selectClip
                    )
                case .completed:
                    BandleResultView(
                        result: model.result,
                        attempts: model.attempts,
                        isPractice: model.isPractice,
                        onPractice: startPractice
                    )
                    BandleAttemptGrid(
                        attempts: model.attempts,
                        currentAttempt: model.currentAttemptNumber,
                        visibleAttempt: model.visibleAttemptNumber,
                        isCompleted: true,
                        onSelect: selectClip
                    )
                    BandleClipControls(clip: model.currentClip, isLoading: model.isLoadingClip, player: clipPlayer)
                }
            }
            .controlSize(.large)
            .padding(AM.Spacing.screenMargin)
            .frame(maxWidth: AM.Layout.wideRailMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .musicScreenBackground()
        .navigationTitle(String(localized: "Daily Bandle"))
        .task { await model.loadIfNeeded() }
        .refreshable { await model.reload() }
        .onChange(of: model.currentClip) { _, clip in
            synchronizeClip(clip)
        }
        .onChange(of: clipPlayer.didFail) { _, didFail in
            if didFail { model.clipPlaybackFailed() }
        }
        .onDisappear(perform: clipPlayer.stop)
    }

    private func selectMode(_ mode: BandleMode) {
        AppHaptic.selection.play()
        clipPlayer.stop()
        Task { await model.selectMode(mode) }
    }

    private func start(excludeFromLeaderboard: Bool) {
        AppHaptic.commit.play()
        Task { await model.start(excludeFromLeaderboard: excludeFromLeaderboard) }
    }

    private func startPractice() {
        AppHaptic.selection.play()
        clipPlayer.stop()
        Task { await model.startPractice() }
    }

    private func submitGuess() {
        AppHaptic.commit.play()
        Task { await model.submitSelectedGuess() }
    }

    private func skip() {
        AppHaptic.selection.play()
        clipPlayer.stop()
        Task { await model.skip() }
    }

    private func selectClip(_ number: Int) {
        AppHaptic.selection.play()
        clipPlayer.stop()
        Task { await model.loadClip(number: number) }
    }

    private func retry() {
        AppHaptic.selection.play()
        Task { await model.retry() }
    }

    private func synchronizeClip(_ clip: BandleAudioClip?) {
        guard let url = clip?.playableURL else {
            clipPlayer.unload()
            return
        }
        clipPlayer.load(url: url)
    }
}
