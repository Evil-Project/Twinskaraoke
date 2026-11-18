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
            if arguments.contains("-UITestSplashWebsites") {
                var fixture = SplashContent.placeholder(.update)
                fixture.enabled = true
                fixture.targetVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                fixture.targetBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                for number in (1...2).reversed() {
                    var slide = SplashSlide()
                    slide.id = "fixture-website-\(number)"
                    slide.website = .init(url: "https://splash-fixture.invalid/form\(number)")
                    fixture.slides.insert(slide, at: 1)
                }
                update = fixture
            }
            if arguments.contains("-UITestSplashChangelogOnly"), var fixture = SplashBundleLoader.runtimeContent(.update) {
                fixture.slides = Array(fixture.slides.prefix(1))
                update = fixture
            }
            // Navigation fixtures must remain stable when release content is edited.
            var install = SplashContent.placeholder(.install)
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
    private var returnedFromBackground = false
    private(set) var isWebsiteOnly = false
    let websiteSession = SplashWebsiteSession()
    private(set) var isBlocking = true
    var isDeveloperTesting: Bool { developerKind != nil }
    private(set) var active: SplashContent? {
        didSet { if oldValue != active { activeFingerprint = active?.fingerprint } }
    }
    private var activeFingerprint: String?
    private(set) var index = 0
    var currentWebsiteStatus: SplashWebsiteProgress.Status? {
        guard let active, active.slides.indices.contains(index), active.slides[index].website != nil,
              let fingerprint = activeFingerprint else { return nil }
        return state?.websites?.first {
            $0.matches(announcementID: active.id, fingerprint: fingerprint, slideID: active.slides[index].id)
        }?.status
    }
    var hasPassedCurrentSlide: Bool {
        if let status = currentWebsiteStatus { return status != .pending }
        return (state?.pending?.highestVisited ?? index) > index
    }
    private(set) var errorMessage: String?
    private(set) var isSaving = false

    /// Configures validated content, release metadata, and separate real and developer history stores.
    init(store: any SplashStateStoring, install: SplashContent, update: SplashContent?,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
         developerSelection: @escaping () -> SplashKind? = { nil },
         developerStore: (any SplashStateStoring)? = nil) {
        self.store = store
        self.developerSelection = developerSelection
        self.developerStore = developerStore ?? SplashStateStore(directory: SplashStateStore.defaultDirectory.appendingPathComponent("DeveloperTesting", isDirectory: true))
        self.install = (try? install.validate(expectedKind: .install)) != nil ? install : .placeholder(.install)
        self.update = update.flatMap {
            guard $0.kind == .update, (try? $0.validateForPresentation(forRelease: true)) != nil else { return nil }
            return $0
        }
        self.version = version; self.build = build
    }

    /// Loads or resumes the required walkthrough, retrying failed persistence when needed.
    func foreground() {
        guard !isSaving else { return }
        if errorMessage != nil { retry(); return }
        if returnedFromBackground, state != nil {
            returnedFromBackground = false
            if resumeWebsiteReminders() { return }
        }
        if !isBlocking {
            guard let kind = developerSelection() else { return }
            beginDeveloperTesting(kind)
        }
        guard state == nil else { return }
        if developerKind == nil { requestedDeveloperKind = developerSelection() }
        do { state = try currentStore.read(); selectPending() }
        catch { fail(error) { [weak self] in self?.foreground() } }
    }
    /// Only a real application background transition arms reminders, not scene inactivity.
    func background() { returnedFromBackground = true }

    /// Resets the chosen real walkthrough only; the caller closes the app after a successful write.
    func resetHistory(_ kind: SplashKind) throws {
        guard !isBlocking, !isSaving else { throw SplashError(message: "Finish the current walkthrough before resetting it.") }
        var candidate = try store.read()
        if kind == .install { candidate.installCompleted = false }
        else {
            guard let update else { throw SplashError(message: "There is no valid bundled update announcement to reset.") }
            candidate.completedUpdateIDs.remove(update.id)
            candidate.websites = nil
        }
        if candidate.pending?.kind == kind { candidate.pending = nil }
        try store.save(candidate)
        state = candidate
    }
    /// Replays the stored failed operation without advancing past unsaved progress.
    func retry() {
        let action = retryOperation; retryOperation = nil; errorMessage = nil; action?()
    }
    /// Selects install before eligible updates, then releases the gate after persisted cleanup.
    private func selectPending() {
        guard var state else { return }
        // Retire records tied to replaced/disabled release content before selecting a reminder.
        let eligibleUpdate = update.flatMap { websiteContentIsEligible($0) ? $0 : nil }
        let fingerprint = eligibleUpdate?.fingerprint
        let websiteIDs = Set(eligibleUpdate?.slides.filter { $0.website != nil }.map(\.id) ?? [])
        let retained = state.websites?.filter {
            $0.announcementID == eligibleUpdate?.id && $0.fingerprint == fingerprint && websiteIDs.contains($0.slideID)
        }
        if retained != state.websites {
            state.websites = retained
            persist(state) { [weak self] in self?.selectPending() }
            return
        }
        if let developerKind {
            if developerKind == .update, resumeWebsiteReminders() { return }
            prepare(developerKind == .install ? install : update ?? .placeholder(.update))
            return
        }
        if !state.installCompleted { prepare(install) }
        else if resumeWebsiteReminders() { return }
        else if let update, update.eligible(version: version, build: build), !state.completedUpdateIDs.contains(update.id) { prepare(update) }
        else {
            // Clear abandoned/ineligible progress, retaining every completion ID.
            if state.pending != nil {
                var candidate = state; candidate.pending = nil
                persist(candidate) { [weak self] in self?.unlock() }
            } else { unlock() }
        }
    }
    /// Resumes matching unfinished content or persists a fresh first-slide position.
    private func prepare(_ content: SplashContent) {
        guard var candidate = state else { return }
        let old = candidate.pending
        let valid = old?.kind == content.kind && old?.id == content.id && old?.fingerprint == content.fingerprint
            && (old?.highestVisited ?? 30) < content.slides.count && (old?.index ?? -1) >= 0
            && (old?.index ?? 30) <= (old?.highestVisited ?? -1)
        let progress = valid ? old! : SplashProgress(kind: content.kind, id: content.id, fingerprint: content.fingerprint, index: 0, highestVisited: 0)
        candidate.pending = progress
        recordWebsite(in: &candidate, content: content, index: progress.index)
        persist(candidate) { [weak self] in
            self?.isWebsiteOnly = false; self?.active = content; self?.index = progress.index
        }
    }
    /// Persists one backward step if the action still matches the rendered walkthrough.
    func back(expectedFingerprint: String? = nil, expectedIndex: Int? = nil) { move(by: -1, fingerprint: expectedFingerprint, from: expectedIndex) }
    func next(expectedFingerprint: String? = nil, expectedIndex: Int? = nil) { move(by: 1, fingerprint: expectedFingerprint, from: expectedIndex) }
    /// Rejects actions from stale scenes by comparing content fingerprints and slide indices.
    private func matchesPresentation(_ fingerprint: String?, _ renderedIndex: Int?) -> Bool {
        (fingerprint == nil || active?.fingerprint == fingerprint) && (renderedIndex == nil || index == renderedIndex)
    }
    /// Persists one valid adjacent slide move after rejecting stale or blocked actions.
    private func move(by delta: Int, fingerprint: String?, from renderedIndex: Int?, updating changes: SplashState? = nil) {
        guard matchesPresentation(fingerprint, renderedIndex), errorMessage == nil, !isSaving,
              let active, var candidate = changes ?? state, var pending = candidate.pending,
              abs(delta) == 1, pending.index == index,
              pending.highestVisited >= index,
              active.slides.indices.contains(index + delta) else { return }
        pending.index += delta; pending.highestVisited = max(pending.highestVisited, pending.index)
        candidate.pending = pending
        recordWebsite(in: &candidate, content: active, index: pending.index)
        persist(candidate) { [weak self] in self?.index = pending.index }
    }
    /// Records completion only at the final visited slide, then selects the next required experience.
    func complete(expectedFingerprint: String? = nil, expectedIndex: Int? = nil) {
        guard matchesPresentation(expectedFingerprint, expectedIndex), errorMessage == nil, !isSaving,
              let active, let candidate = state, let pending = candidate.pending,
              pending.fingerprint == active.fingerprint, pending.id == active.id, pending.kind == active.kind,
              index == active.slides.count - 1, pending.index == index, pending.highestVisited == index else { return }
        finishWalkthrough(candidate)
    }

    /// Both native Done and website completion commit through this same final-slide path.
    private func finishWalkthrough(_ state: SplashState) {
        guard let active else { return }
        var candidate = state
        if developerKind != nil {
            if pendingWebsiteIndices(in: candidate, content: active).isEmpty {
                let fingerprint = activeFingerprint ?? active.fingerprint
                candidate.websites?.removeAll { $0.announcementID == active.id && $0.fingerprint == fingerprint }
            }
            candidate.pending = nil
            persist(candidate) { [weak self] in
                guard let self else { return }
                self.developerKind = nil; self.state = self.runtimeState; self.runtimeState = nil
                self.unlock()
            }
            return
        }
        if active.kind == .install { candidate.installCompleted = true }
        else if pendingWebsiteIndices(in: candidate, content: active).isEmpty { candidate.completedUpdateIDs.insert(active.id) }
        candidate.pending = nil
        persist(candidate) { [weak self] in
            guard let self else { return }
            if active.kind == .update { self.unlock() }
            else { self.active = nil; self.selectPending() }
        }
    }
    /// Writes candidate state before publishing UI changes, retaining a retry on failure.
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
    /// Keeps the gate blocked and stores the operation that can recover from the error.
    private func fail(_ error: Error, retry: @escaping () -> Void) {
        errorMessage = "Walkthrough data could not be saved or loaded. \(error.localizedDescription)"
        retryOperation = retry
    }
    /// Switches to isolated test history while retaining the real runtime completion state.
    private func beginDeveloperTesting(_ kind: SplashKind) {
        runtimeState = state; state = nil; active = nil
        developerKind = kind; requestedDeveloperKind = nil; isBlocking = true; isWebsiteOnly = false
    }
    /// Performs the version-tap sequence to enable the hidden Developer menu.
    private func unlock() {
        if let kind = requestedDeveloperKind {
            beginDeveloperTesting(kind); foreground(); return
        }
        active = nil; isBlocking = false; isWebsiteOnly = false
        AppRouter.shared.resumeAfterSplash()
    }
}

private extension SplashCoordinator {
    func websiteContentIsEligible(_ content: SplashContent) -> Bool {
        developerKind == .update || content.eligible(version: version, build: build)
    }

    func pendingWebsiteIndices(in state: SplashState, content: SplashContent) -> [Int] {
        let fingerprint = content.fingerprint
        let pendingIDs = Set((state.websites ?? []).filter {
            $0.announcementID == content.id && $0.fingerprint == fingerprint && $0.status == .pending
        }.map(\.slideID))
        return content.slides.indices.filter {
            content.slides[$0].website != nil && pendingIDs.contains(content.slides[$0].id)
        }
    }

    func recordWebsite(in state: inout SplashState, content: SplashContent, index: Int) {
        guard content.slides[index].website != nil else { return }
        var records = state.websites ?? []
        let fingerprint = content.fingerprint
        guard !records.contains(where: {
            $0.matches(announcementID: content.id, fingerprint: fingerprint, slideID: content.slides[index].id)
        }) else { return }
        // Old versions used only highestVisited; preserve their already-passed website steps.
        let passed = (state.pending?.highestVisited ?? index) > index
        records.append(SplashWebsiteProgress(announcementID: content.id, fingerprint: fingerprint,
                                             slideID: content.slides[index].id, status: passed ? .completed : .pending))
        state.websites = records
    }

    /// Selects only previously encountered unresolved forms, keeping a visible form alive.
    @discardableResult func resumeWebsiteReminders() -> Bool {
        guard var candidate = state, candidate.installCompleted || developerKind == .update,
              let update, websiteContentIsEligible(update) else { return false }
        let indices = pendingWebsiteIndices(in: candidate, content: update)
        guard let first = indices.first else { return false }
        let keepVisible = active?.fingerprint == update.fingerprint && indices.contains(index)
        let selected = keepVisible ? index : first
        candidate.pending = SplashProgress(kind: .update, id: update.id, fingerprint: update.fingerprint,
                                           index: selected, highestVisited: max(selected, candidate.pending?.highestVisited ?? 0))
        isBlocking = true
        let publish = { [weak self] in
            self?.isWebsiteOnly = true; self?.isBlocking = true; self?.active = update; self?.index = selected
        }
        if candidate.pending == state?.pending { publish() }
        else { persist(candidate, success: publish) }
        return true
    }
}

extension SplashCoordinator {
    /// Resolves exactly the rendered website. The candidate also contains its navigation save.
    func websiteAction(_ action: SplashWebsiteAction, expectedFingerprint: String, expectedIndex: Int) {
        guard matchesPresentation(expectedFingerprint, expectedIndex), errorMessage == nil, !isSaving,
              let active, active.slides.indices.contains(index), active.slides[index].website != nil,
              var candidate = state, var records = candidate.websites,
              let recordIndex = records.firstIndex(where: {
                  $0.matches(announcementID: active.id, fingerprint: expectedFingerprint, slideID: active.slides[index].id)
              })
        else { return }
        let previousStatus = records[recordIndex].status
        guard previousStatus == .pending || (previousStatus == .closed && action == .deferred) else { return }
        if action != .deferred {
            guard let status = SplashWebsiteProgress.Status(rawValue: action.rawValue) else { return }
            records[recordIndex].status = status
            candidate.websites = records
        }
        // A 410 resolves immediately, while retaining a native Continue action on this screen.
        if action == .closed {
            if isWebsiteOnly, pendingWebsiteIndices(in: candidate, content: active).isEmpty {
                candidate.completedUpdateIDs.insert(active.id)
                candidate.pending = nil
            }
            persist(candidate) {}
            return
        }
        if isWebsiteOnly {
            candidate.pending = nil
            let remaining = pendingWebsiteIndices(in: candidate, content: active)
            if remaining.isEmpty {
                candidate.completedUpdateIDs.insert(active.id)
                if developerKind != nil {
                    let fingerprint = activeFingerprint ?? active.fingerprint
                    candidate.websites?.removeAll { $0.announcementID == active.id && $0.fingerprint == fingerprint }
                }
            }
            if action == .deferred, previousStatus == .pending {
                persist(candidate) { [weak self] in self?.finishWebsitePresentation() }
            } else if let next = remaining.first {
                candidate.pending = SplashProgress(kind: .update, id: active.id, fingerprint: active.fingerprint,
                                                   index: next, highestVisited: next)
                persist(candidate) { [weak self] in self?.index = next }
            } else {
                persist(candidate) { [weak self] in self?.finishWebsitePresentation() }
            }
        } else {
            // Reuse the regular forward transition, with the outcome included in the same write.
            advanceWebsite(candidate)
        }
    }

    private func advanceWebsite(_ candidate: SplashState) {
        guard let active else { return }
        if index < active.slides.count - 1 {
            move(by: 1, fingerprint: active.fingerprint, from: index, updating: candidate)
        } else {
            finishWalkthrough(candidate)
        }
    }

    private func finishWebsitePresentation() {
        if developerKind != nil {
            developerKind = nil; state = runtimeState; runtimeState = nil
        }
        unlock()
    }
}
