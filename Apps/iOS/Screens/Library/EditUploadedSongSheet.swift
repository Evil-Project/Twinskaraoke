import SwiftUI

/// Changes the title and artist of one of the user's uploads. The server
/// keeps the artist as one string, so it is edited as one field.
struct EditUploadedSongSheet: View {
    let song: Song
    let save: (UploadedSongEdit) async -> UploadedSongsViewModel.EditOutcome

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @State private var isSaving = false
    @State private var failure: SongUploadFailure?

    init(song: Song, save: @escaping (UploadedSongEdit) async -> UploadedSongsViewModel.EditOutcome) {
        self.song = song
        self.save = save
        _title = State(initialValue: song.title)
        _artist = State(initialValue: UploadedSongsViewModel.artistText(for: song))
    }

    private var edit: UploadedSongEdit {
        UploadedSongEdit(title: title, artist: artist)
    }

    private var titleIsEmpty: Bool {
        UploadedSongsViewModel.trimmed(edit).title.isEmpty
    }

    private var canSave: Bool {
        !isSaving && !titleIsEmpty && !UploadedSongsViewModel.isUnchanged(edit, for: song)
    }

    private var serverProblem: UploadServerProblem? {
        if case let .server(_, problem) = failure { problem } else { nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .accessibilityIdentifier("EditUpload.Title")
                } header: {
                    Text("Title")
                } footer: {
                    if titleIsEmpty {
                        problemText(String(localized: "Enter a title."))
                    } else if let message = serverProblem?.message(forField: "Title") {
                        problemText(message)
                    }
                }

                Section {
                    TextField("Artist", text: $artist)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { if canSave { submit() } }
                        .accessibilityIdentifier("EditUpload.Artist")
                } header: {
                    Text("Artist")
                } footer: {
                    if let message = serverProblem?.message(forField: "Artist") {
                        problemText(message)
                    } else if let failure, serverProblem?.fieldErrors.isEmpty != false {
                        problemText(failure.userMessage)
                    }
                }
            }
            .navigationTitle("Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppHaptic.dismiss.play()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: submit)
                            .disabled(!canSave)
                            .accessibilityIdentifier("EditUpload.Save")
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .accessibilityIdentifier("EditUpload.Sheet")
    }

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

    private func submit() {
        guard canSave else { return }
        // One haptic per save, for its result.
        isSaving = true
        failure = nil
        Task {
            let outcome = await save(edit)
            isSaving = false
            switch outcome {
            case .saved, .unchanged:
                AppHaptic.success.play()
                dismiss()
            case .emptyTitle:
                break
            case let .failed(reason):
                AppHaptic.error.play()
                failure = reason
            }
        }
    }
}
