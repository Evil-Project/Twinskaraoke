import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import Observation

struct SplashJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    /// Wraps already encoded JSON bytes for export.
    init(data: Data) { self.data = data }
    /// Validates and encodes a self-contained walkthrough for export.
    init(content: SplashContent) throws {
        try content.validateForPresentation(forRelease: true)
        data = try content.encoded()
    }
    /// Reads and validates imported JSON before creating the document.
    init(configuration: ReadConfiguration) throws {
        let bytes = configuration.file.regularFileContents ?? Data()
        data = try SplashContent.decode(bytes).encoded()
    }
    /// Packages embedded document bytes for the system file exporter.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor @Observable final class SplashStudioModel {
    var draft: SplashContent
    var message: String? { didSet { noticeRevision += 1 } }
    var noticeRevision = 0
    private let directory: URL
    /// Loads the selected bundled walkthrough and any saved draft from the supplied directory.
    init(kind: SplashKind = .install, directory: URL = SplashStateStore.defaultDirectory.appendingPathComponent("Drafts")) {
        self.directory = directory
        draft = (try? SplashBundleLoader.load(kind)) ?? .placeholder(kind)
        loadDraft(kind)
        reserveReleaseNotes()
    }
    /// Returns the local draft path for one walkthrough kind.
    private func file(_ kind: SplashKind) -> URL { directory.appendingPathComponent("\(kind.rawValue).json") }
    /// Loads the saved draft, reporting corrupt content while retaining bundled defaults.
    func loadDraft(_ kind: SplashKind) {
        do { draft = try SplashContent.decode(Data(contentsOf: file(kind)), expectedKind: kind) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { }
        catch { message = "Could not load local draft: \(error.localizedDescription)" }
    }
    /// Validates and atomically saves the draft, optionally announcing success in the notice bubble.
    @discardableResult func saveDraft(announce: Bool = true) -> Bool {
        do {
            let data = try draft.encoded()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            try data.write(to: file(draft.kind), options: .atomic)
            url = file(draft.kind); try url.setResourceValues(values)
            if announce { message = "Draft saved locally." }; return true
        } catch { message = error.localizedDescription; return false }
    }
    /// Saves the outgoing draft before loading the other walkthrough kind.
    func switchMode(_ kind: SplashKind) {
        guard kind != draft.kind, saveDraft(announce: false) else { return }
        draft = (try? SplashBundleLoader.load(kind)) ?? .placeholder(kind)
        message = nil; loadDraft(kind)
        reserveReleaseNotes()
    }
    /// Replaces the draft only after the imported JSON validates for the selected kind.
    func importData(_ data: Data) throws {
        draft = try SplashContent.decode(data, expectedKind: draft.kind)
        reserveReleaseNotes()
    }
    func reserveReleaseNotes() {
        guard draft.kind == .update, draft.slides.first?.releaseNotes == nil, draft.slides.count < 30 else { return }
        draft.slides.insert(.releaseNotesPage(), at: 0)
    }
    func move(_ offsets: IndexSet, to destination: Int) {
        if draft.slides.first?.releaseNotes != nil, offsets.contains(0) || destination == 0 { return }
        draft.slides.move(fromOffsets: offsets, toOffset: destination)
    }
    func delete(_ offsets: IndexSet) {
        let removable = offsets.filter { draft.slides[$0].releaseNotes == nil }
        guard draft.slides.count > removable.count else { message = String(localized: "Keep at least one slide."); return }
        draft.slides.remove(atOffsets: IndexSet(removable))
        reserveReleaseNotes()
    }
    func binding(for slide: SplashSlide) -> Binding<SplashSlide> {
        var current = slide
        return Binding(
            get: { self.draft.slides.first { $0.id == current.id } ?? current },
            set: { updated in
                guard let index = self.draft.slides.firstIndex(where: { $0.id == current.id }) else { return }
                guard !self.draft.slides.enumerated().contains(where: { $0.offset != index && $0.element.id == updated.id }) else {
                    self.message = String(localized: "Slide IDs must be unique.")
                    return
                }
                self.draft.slides[index] = updated
                current = updated
            }
        )
    }
    /// Inserts a copy with a new slide ID without exceeding the thirty-slide limit.
    func duplicate(_ index: Int) {
        guard draft.slides.count < 30, draft.slides[index].releaseNotes == nil else { return }
        var copy = draft.slides[index]; copy.id = UUID().uuidString
        draft.slides.insert(copy, at: index + 1)
    }
    /// Assigns a fresh update identity so a future release can be announced once.
    func newAnnouncement() { guard draft.kind == .update else { return }; draft.id = UUID().uuidString }
}

struct SplashStudioView: View {
    @State private var model: SplashStudioModel
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = SplashJSONDocument(data: Data())
    @State private var preview: SplashContent?
    @State private var confirmReload = false
    @State private var confirmProposal = false
    @Environment(\.scenePhase) private var phase
    /// Uses the supplied Studio model or creates one backed by local draft storage.
    init(model: SplashStudioModel? = nil) {
        _model = State(initialValue: model ?? SplashStudioModel())
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if DeveloperMode.isEnabled {
                List {
                    Section("Content") {
                        Picker("Walkthrough", selection: Binding(get: { model.draft.kind }, set: { kind in model.switchMode(kind) })) {
                            ForEach(SplashKind.allCases) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        TextField("Content ID", text: $model.draft.id)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if model.draft.kind == .update {
                            Toggle("Show Update Walkthrough for This Release", isOn: $model.draft.enabled)
                            Text("Leave this off when a release needs no announcement. Export update.json, replace the bundled source file, then rebuild. First-install onboarding is separate.")
                                .font(.caption)
                            TextField("Target marketing version", text: optional($model.draft.targetVersion))
                                .keyboardType(.numbersAndPunctuation)
                            TextField("Target build (optional)", text: optional($model.draft.targetBuild))
                                .keyboardType(.numbersAndPunctuation)
                            Button("New Announcement", action: model.newAnnouncement)
                            Text("Ordinary edits preserve this ID. Use New Announcement only for a new release announcement.")
                                .font(.caption)
                        }
                        TextField("Next button label", text: $model.draft.nextLabel)
                        TextField("Final button label", text: $model.draft.finalLabel)
                    }
                    Section("Slides — drag to reorder in Edit mode") {
                        ForEach(Array(model.draft.slides.enumerated()), id: \.element.id) { index, slide in
                            if slide.releaseNotes != nil {
                                NavigationLink("Release notes") {
                                    SplashReleaseNotesEditor(slide: model.binding(for: slide))
                                }
                                .moveDisabled(true)
                                .deleteDisabled(true)
                            } else {
                                NavigationLink {
                                    SplashSlideEditor(slide: model.binding(for: slide), allowsWebsite: model.draft.kind == .update, studio: model)
                                } label: {
                                    VStack(alignment: .leading) {
                                        if slide.website != nil {
                                            Text("Website")
                                        } else {
                                            Text("\(index + 1). \(slide.title ?? "Untitled slide")")
                                        }
                                        Text(slide.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Duplicate") { model.duplicate(index) }.tint(.blue)
                                }
                                .contextMenu { Button("Duplicate") { model.duplicate(index) } }
                            }
                        }
                        .onMove(perform: model.move)
                        .onDelete(perform: model.delete)
                        Button("Add Slide") { model.draft.slides.append(SplashSlide()) }.disabled(model.draft.slides.count >= 30)
                    }
                    Section("Draft and preview") {
                        Button("Save Local Draft") {
                            if model.saveDraft() { AppHaptic.success.play() }
                        }.accessibilityIdentifier("SplashStudio.SaveDraft")
                        Button("Load Bundled Content") { confirmReload = true }
                        if model.draft.kind == .install {
                            Button("Load Proposed Install Walkthrough") { confirmProposal = true }
                        }
                        Button("Import JSON") { importing = true }
                        Button("Preview") {
                            do { try model.draft.validateForPresentation(); preview = model.draft }
                            catch { model.message = error.localizedDescription }
                        }.accessibilityIdentifier("SplashStudio.Preview")
                        Button("Export \(model.draft.kind.rawValue).json") {
                            do { exportDocument = try SplashJSONDocument(content: model.draft); exporting = true }
                            catch { model.message = error.localizedDescription }
                        }.accessibilityIdentifier("SplashStudio.Export")
                    }
                    Section("Publish") {
                        Text("Replace Apps/iOS/Resources/SplashScreens/\(model.draft.kind.rawValue).json in the repository with the exported file, then build and ship a new release. Exporting cannot change an installed app’s bundle.")
                            .font(.callout).textSelection(.enabled)
                    }
                }
                .toolbar { EditButton() }
            } else { Text("Developer mode is required.") }
        }
        .navigationTitle("Splash Screen Studio")
        .navigationBarTitleDisplayMode(.inline)
        .splashNotice($model.message, revision: model.noticeRevision)
        .confirmationDialog("Replace the current install draft with the proposed walkthrough?", isPresented: $confirmProposal, titleVisibility: .visible) {
            Button("Load Proposal", role: .destructive) {
                do { model.draft = try SplashBundledAssets.proposedInstall(); model.message = nil }
                catch { model.message = error.localizedDescription }
            }
        }
        .confirmationDialog("Replace the current draft with bundled content?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Load Bundled Content", role: .destructive) {
                do {
                    model.draft = try SplashBundleLoader.load(model.draft.kind)
                    model.reserveReleaseNotes()
                    model.message = nil
                } catch { model.message = error.localizedDescription }
            }
        }
        .background {
            Color.clear.fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= SplashContent.maxFileBytes else { throw SplashError(message: "JSON exceeds 12 MB.") }
                    try model.importData(Data(contentsOf: url)); model.message = "Imported into the draft."
                } catch {
                    if (error as NSError).code != NSUserCancelledError { model.message = error.localizedDescription }
                }
            }
        }
        .background {
            Color.clear.fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                                     defaultFilename: model.draft.kind.rawValue) { result in
                switch result {
                case .success: model.message = "Export succeeded. Copy the JSON to the source path below and rebuild."
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { model.message = "Export failed: \(error.localizedDescription)" }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview { SplashPreviewView(content: preview) }
        }
        .onChange(of: phase) { _, phase in if phase == .background { model.saveDraft(announce: false) } }
        .onDisappear { model.saveDraft(announce: false) }
    }
    /// Maps empty editor text to a nil optional content field.
    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

struct SplashPreviewView: View {
    let content: SplashContent
    @State private var index = 0
    @State private var resolvedWebsites: Set<String> = []
    @State private var closedWebsites: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        SplashWalkthroughView(content: content, index: index,
                              websiteCompleted: resolvedWebsites.contains(content.slides[index].id),
                              websiteClosed: closedWebsites.contains(content.slides[index].id),
                              websiteIsPreview: true,
                              websiteAction: { action in
                                  if action != .deferred { resolvedWebsites.insert(content.slides[index].id) }
                                  if action == .closed { closedWebsites.insert(content.slides[index].id) }
                                  else if index == content.slides.count - 1 { dismiss() }
                                  else { index += 1 }
                              },
                              back: { index = max(0, index - 1) },
                              next: {
                                  index = min(content.slides.count - 1, index + 1)
                              },
                              complete: { dismiss() }, retry: {})
            .safeAreaInset(edge: .top) {
                HStack { Text("Preview"); Spacer(); Button("Exit Preview") { dismiss() } }
                    .padding().background(.regularMaterial)
            }
    }
}

struct SplashSlideEditor: View {
    @Binding var slide: SplashSlide
    var allowsWebsite = false
    var studio: SplashStudioModel? = nil
    @State private var message: String?
    @State private var singlePreview = false
    @State private var arranging = false
    var body: some View {
        Form {
            if allowsWebsite {
                SplashWebsiteEditor(website: $slide.website)
            }
            if slide.website == nil { SplashStandardSlideFields(slide: $slide, message: $message, singlePreview: $singlePreview, arranging: $arranging) }
            else {
                DisclosureGroup("Standard slide settings") { SplashStandardSlideFields(slide: $slide, message: $message, singlePreview: $singlePreview, arranging: $arranging) }
            }
        }
        .accessibilityIdentifier("SplashStudio.SlideForm")
        .navigationTitle("Edit Slide")
        .onChange(of: studio?.noticeRevision) { _, _ in if let notice = studio?.message { message = notice } }
        .splashNotice($message, revision: studio?.noticeRevision ?? 0)
        .fullScreenCover(isPresented: $singlePreview) {
            SplashPreviewView(content: SplashContent(kind: .install, id: "single-preview", slides: [slide]))
        }
        .fullScreenCover(isPresented: $arranging) { SplashCanvasEditor(slide: $slide) }
    }
}
