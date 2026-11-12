import SwiftUI
import UniformTypeIdentifiers

/// Adds a song to the user's uploads, from an audio file or a link.
///
/// Submitting hands the song to `SongUploadController` and closes the sheet;
/// the upload goes on there, and the Uploaded list shows its progress. What
/// the sheet can check itself, a link it can't import or a full quota, stays
/// here and keeps the submit button off.
struct UploadSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var form = UploadSongFormModel()
    @State private var isChoosingFile = false
    @State private var pickFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $form.mode) {
                        Text("File").tag(UploadSongFormModel.Mode.file)
                        Text("Link").tag(UploadSongFormModel.Mode.link)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("UploadSong.Mode")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch form.mode {
                case .file:
                    fileSections
                case .link:
                    linkSection
                }

                storageSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Upload a Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.audio]) { result in
                switch result {
                case let .success(url):
                    pickFailed = false
                    Task { await form.pick(url) }
                case let .failure(error):
                    pickFailed = (error as NSError).code != NSUserCancelledError
                }
            }
            .selectionHaptic(form.mode)
            .task { await form.loadLimits() }
        }
        .accessibilityIdentifier("UploadSong.Sheet")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                AppHaptic.dismiss.play()
                dismiss()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Group {
                if form.mode == .file {
                    Button("Upload", action: submit)
                } else {
                    Button("Import", action: submit)
                }
            }
            .disabled(!form.canSubmit)
            .accessibilityIdentifier("UploadSong.Submit")
        }
    }

    // MARK: - File

    @ViewBuilder
    private var fileSections: some View {
        Section {
            Button {
                AppHaptic.selection.play()
                isChoosingFile = true
            } label: {
                Label("Choose Audio File", systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("UploadSong.ChooseFile")

            if let file = form.file {
                LabeledContent {
                    if let size = file.size {
                        Text(verbatim: SongUploadFailure.size(size))
                    }
                } label: {
                    Text(verbatim: file.name)
                        .lineLimit(3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("UploadSong.File")
            }
        } footer: {
            if pickFailed {
                problemText(SongUploadFailure.fileUnreadable.userMessage)
            } else if form.isAlreadyUploading {
                alreadyUploadingText
            } else if let quotaMessage = form.quotaMessage {
                problemText(quotaMessage)
            }
        }

        Section {
            TextField("Title", text: $form.title)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .accessibilityIdentifier("UploadSong.Title")
        } header: {
            Text("Title")
        } footer: {
            if let error = form.fieldError("Title") {
                problemText(error)
            }
        }

        Section {
            TextField("Artist", text: $form.artist)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .accessibilityIdentifier("UploadSong.Artist")
        } header: {
            Text("Artist")
        } footer: {
            if let error = form.fieldError("Artist") {
                problemText(error)
            }
        }
    }

    // MARK: - Link

    private var linkSection: some View {
        Section {
            TextField("Paste a Link", text: $form.linkText)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { if form.canSubmit { submit() } }
                .accessibilityIdentifier("UploadSong.Link")
        } header: {
            Text("Link")
        } footer: {
            VStack(alignment: .leading, spacing: AM.Spacing.s) {
                if form.isAlreadyUploading {
                    alreadyUploadingText
                } else if let problem = form.linkProblem {
                    problemText(SongUploadFailure.unsupportedLink(problem).userMessage)
                        .accessibilityIdentifier("UploadSong.LinkProblem")
                } else if let quotaMessage = form.quotaMessage {
                    problemText(quotaMessage)
                }
                Text("Works with YouTube, Bilibili and Discord attachment links. The song takes its title from the link.")
            }
        }
    }

    // MARK: - Storage

    @ViewBuilder
    private var storageSection: some View {
        if let limits = form.limits {
            Section("Storage") {
                StorageMeterRow(
                    icon: "music.note",
                    label: String(localized: "Songs Uploaded"),
                    valueText: "\(limits.currentSongCount)/\(limits.maxSongs)",
                    ratio: Self.ratio(Double(limits.currentSongCount), Double(limits.maxSongs)),
                    barHeight: 4
                )
                .accessibilityElement(children: .combine)
                StorageMeterRow(
                    icon: "internaldrive",
                    label: String(localized: "Storage Used"),
                    valueText: "\(SongUploadFailure.size(limits.usedStorageBytes)) / \(SongUploadFailure.size(limits.maxStorageBytes))",
                    ratio: Self.ratio(Double(limits.usedStorageBytes), Double(limits.maxStorageBytes)),
                    barHeight: 6
                )
                .accessibilityElement(children: .combine)
            }
        } else if form.limitsUnavailable {
            Section("Storage") {
                Text("Your storage limits couldn't be loaded. You can still upload.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func problemText(_ message: String) -> some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.appDestructive)
        .accessibilityElement(children: .combine)
    }

    private static var alreadyUploadingMessage: String {
        String(localized: "This is already uploading. Its progress shows under Uploaded.")
    }

    private var alreadyUploadingText: some View {
        problemText(Self.alreadyUploadingMessage)
            .accessibilityIdentifier("UploadSong.AlreadyUploading")
    }

    private static func ratio(_ value: Double, _ limit: Double) -> Double {
        limit > 0 ? value / limit : 0
    }

    private func submit() {
        guard let submission = form.submission else { return }
        // The same file or link already on its way is ignored: say so and
        // stay open instead of announcing a start.
        guard form.submit(to: SongUploadController.shared) else {
            AccessibilityNotification.Announcement(Self.alreadyUploadingMessage).post()
            return
        }
        let announcement = switch submission {
        case .file: String(localized: "Upload started.")
        case .link: String(localized: "Import started.")
        }
        AppHaptic.commit.play()
        AccessibilityNotification.Announcement(announcement).post()
        dismiss()
    }
}
