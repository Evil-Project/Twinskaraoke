import Foundation
import Observation

@MainActor @Observable final class SplashCoordinator {
    static let shared: SplashCoordinator = {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if AppRuntime.isUITestMode && !arguments.contains("-UITestSplash") {
            let coordinator = SplashCoordinator(store: SplashStateStore(), install: .placeholder(.install), update: nil)
            coordinator.isBlocking = false
            return coordinator
        }
        if AppRuntime.isUITestMode && arguments.contains("-UITestSplash") {
            if arguments.contains("-UITestSplashResetControls") {
                DeveloperMode.isEnabled = true
                UserDefaults.standard.set("off", forKey: DeveloperMode.splashTestingKey)
            }
            let directory = SplashStateStore.defaultDirectory.appendingPathComponent("UITest", isDirectory: true)
            if arguments.contains("-UITestSplashReset") { try? FileManager.default.removeItem(at: directory) }
            var update: SplashContent?
            if arguments.contains("-UITestSplashUpdate") {
                update = .placeholder(.update); update?.enabled = true; update?.targetVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            }
            var install = SplashBundleLoader.runtimeContent(.install)!
            if arguments.contains("-UITestSplashLongContent") {
                install.slides[0].body = String(repeating: "Description placeholder. ", count: 300)
                install.slides[0].alignment = .leading
                install.slides[0].backgroundColor = "#FFFFFF"
                install.slides[0].textColor = "#101827"
            }
            if arguments.contains("-UITestSplashDesign") { install = SplashStudioTestingFixtures.content }
            return SplashCoordinator(store: SplashStateStore(directory: directory), install: install,
                                     update: update ?? SplashBundleLoader.runtimeContent(.update),
                                     developerSelection: { arguments.contains("-UITestSplashDeveloperControls") ? DeveloperMode.splashTestingKind : nil },
                                     developerStore: SplashStateStore(directory: directory.appendingPathComponent("DeveloperTesting")))
        }
        #endif
        return SplashCoordinator(store: SplashStateStore(), install: SplashBundleLoader.runtimeContent(.install)!, update: SplashBundleLoader.runtimeContent(.update), developerSelection: { DeveloperMode.splashTestingKind })
    }()

    private let store: any SplashStateStoring
    private let developerStore: any SplashStateStoring
    private let developerSelection: () -> SplashKind?
    private var developerKind: SplashKind?
    private var requestedDeveloperKind: SplashKind?
    private var runtimeState: SplashState?
    private var currentStore: any SplashStateStoring { developerKind == nil ? store : developerStore }
    private let install: SplashContent
    private let update: SplashContent?
    private let version: String
    private let build: String
    private var state: SplashState?
    private var retryOperation: (() -> Void)?
    private(set) var isBlocking = true
    var isDeveloperTesting: Bool { developerKind != nil }
    private(set) var active: SplashContent?
    private(set) var index = 0
    private(set) var errorMessage: String?
    private(set) var isSaving = false

    init(store: any SplashStateStoring, install: SplashContent, update: SplashContent?,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
         developerSelection: @escaping () -> SplashKind? = { nil },
         developerStore: (any SplashStateStoring)? = nil) {
        self.store = store
        self.developerSelection = developerSelection
        self.developerStore = developerStore ?? SplashStateStore(directory: SplashStateStore.defaultDirectory.appendingPathComponent("DeveloperTesting", isDirectory: true))
        self.install = (try? install.validate(expectedKind: .install)) != nil ? install : .placeholder(.install)
        self.update = update.flatMap { (try? $0.validate(expectedKind: .update)) != nil ? $0 : nil }
        self.version = version; self.build = build
    }

    func foreground() {
        guard !isSaving else { return }
        if !isBlocking {
            guard let kind = developerSelection() else { return }
            beginDeveloperTesting(kind)
        }
        if errorMessage != nil { retry(); return }
        guard state == nil else { return }
        if developerKind == nil { requestedDeveloperKind = developerSelection() }
        do { state = try currentStore.read(); selectPending() }
        catch { fail(error) { [weak self] in self?.foreground() } }
    }
    /// Resets the chosen real walkthrough only; the caller closes the app after a successful write.
    func resetHistory(_ kind: SplashKind) throws {
        guard !isBlocking, !isSaving else { throw SplashError(message: "Finish the current walkthrough before resetting it.") }
        var candidate = try store.read()
        if kind == .install { candidate.installCompleted = false }
        else {
            guard let update else { throw SplashError(message: "There is no valid bundled update announcement to reset.") }
            candidate.completedUpdateIDs.remove(update.id)
        }
        if candidate.pending?.kind == kind { candidate.pending = nil }
        try store.save(candidate)
        state = candidate
    }
    func retry() {
        let action = retryOperation; retryOperation = nil; errorMessage = nil; action?()
    }
    private func selectPending() {
        guard let state else { return }
        if let developerKind {
            prepare(developerKind == .install ? install : update ?? .placeholder(.update))
            return
        }
        if !state.installCompleted { prepare(install) }
        else if let update, update.eligible(version: version, build: build), !state.completedUpdateIDs.contains(update.id) { prepare(update) }
        else {
            // Clear abandoned/ineligible progress, retaining every completion ID.
            if state.pending != nil {
                var candidate = state; candidate.pending = nil
                persist(candidate) { [weak self] in self?.unlock() }
            } else { unlock() }
        }
    }
    private func prepare(_ content: SplashContent) {
        guard var candidate = state else { return }
        let old = candidate.pending
        let valid = old?.kind == content.kind && old?.id == content.id && old?.fingerprint == content.fingerprint
            && (old?.highestVisited ?? 30) < content.slides.count && (old?.index ?? -1) >= 0
            && (old?.index ?? 30) <= (old?.highestVisited ?? -1)
        let progress = valid ? old! : SplashProgress(kind: content.kind, id: content.id, fingerprint: content.fingerprint, index: 0, highestVisited: 0)
        candidate.pending = progress
        persist(candidate) { [weak self] in self?.active = content; self?.index = progress.index }
    }
    func back(expectedFingerprint: String? = nil, expectedIndex: Int? = nil) { move(by: -1, fingerprint: expectedFingerprint, from: expectedIndex) }
    func next(expectedFingerprint: String? = nil, expectedIndex: Int? = nil) { move(by: 1, fingerprint: expectedFingerprint, from: expectedIndex) }
    private func matchesPresentation(_ fingerprint: String?, _ renderedIndex: Int?) -> Bool {
        (fingerprint == nil || active?.fingerprint == fingerprint) && (renderedIndex == nil || index == renderedIndex)
    }
    private func move(by delta: Int, fingerprint: String?, from renderedIndex: Int?) {
        guard matchesPresentation(fingerprint, renderedIndex), errorMessage == nil, !isSaving, let active, var candidate = state, var pending = candidate.pending,
              abs(delta) == 1, pending.index == index,
              pending.highestVisited >= index,
              active.slides.indices.contains(index + delta) else { return }
        pending.index += delta; pending.highestVisited = max(pending.highestVisited, pending.index)
        candidate.pending = pending
        persist(candidate) { [weak self] in self?.index = pending.index }
    }
    func complete(expectedFingerprint: String? = nil, expectedIndex: Int? = nil) {
        guard matchesPresentation(expectedFingerprint, expectedIndex), errorMessage == nil, !isSaving, let active, var candidate = state, let pending = candidate.pending,
              pending.fingerprint == active.fingerprint, pending.id == active.id, pending.kind == active.kind,
              index == active.slides.count - 1, pending.index == index, pending.highestVisited == index else { return }
        if developerKind != nil {
            candidate.pending = nil
            persist(candidate) { [weak self] in
                guard let self else { return }
                self.developerKind = nil; self.state = self.runtimeState; self.runtimeState = nil
                self.unlock()
            }
            return
        }
        if active.kind == .install { candidate.installCompleted = true }
        else { candidate.completedUpdateIDs.insert(active.id) }
        candidate.pending = nil
        persist(candidate) { [weak self] in self?.active = nil; self?.selectPending() }
    }
    private func persist(_ candidate: SplashState, success: @escaping () -> Void) {
        guard !isSaving else { return }
        isSaving = true
        do {
            try currentStore.save(candidate); state = candidate; isSaving = false
            errorMessage = nil; retryOperation = nil; success()
        } catch {
            isSaving = false
            fail(error) { [weak self] in self?.persist(candidate, success: success) }
        }
    }
    private func fail(_ error: Error, retry: @escaping () -> Void) {
        errorMessage = "Walkthrough data could not be saved or loaded. \(error.localizedDescription)"
        retryOperation = retry
    }
    private func beginDeveloperTesting(_ kind: SplashKind) {
        runtimeState = state; state = nil; active = nil
        developerKind = kind; requestedDeveloperKind = nil; isBlocking = true
    }
    private func unlock() {
        if let kind = requestedDeveloperKind {
            beginDeveloperTesting(kind); foreground(); return
        }
        active = nil; isBlocking = false
        AppRouter.shared.resumeAfterSplash()
    }
}
