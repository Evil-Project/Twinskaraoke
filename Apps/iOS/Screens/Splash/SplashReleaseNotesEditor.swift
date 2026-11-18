import SwiftUI

struct SplashReleaseNotesEditor: View {
    @Binding var slide: SplashSlide

    var body: some View {
        Form {
            Section("Release notes") {
                TextField("Title (optional)", text: Binding(
                    get: { slide.title ?? "" },
                    set: { slide.title = $0.isEmpty ? nil : $0 }
                ))
            }
            if let notes = Binding($slide.releaseNotes) {
                Section("watchOS") {
                    TextField("watchOS version", text: notes.watchVersion)
                        .keyboardType(.numbersAndPunctuation)
                    SplashReleaseEntryEditor(entries: notes.watchOS)
                }
                Section("iOS") { SplashReleaseEntryEditor(entries: notes.iOS) }
                Section("General") { SplashReleaseEntryEditor(entries: notes.general) }
            }
        }
        .navigationTitle("Release notes")
    }
}

private struct SplashReleaseEntryEditor: View {
    @Binding var entries: [SplashReleaseNotes.Entry]

    var body: some View {
        ForEach($entries) { $entry in
            VStack(alignment: .leading, spacing: AM.Spacing.s) {
                TextField("Headline", text: $entry.headline, axis: .vertical)
                TextField("Details (one per line)", text: $entry.details, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .onDelete { entries.remove(atOffsets: $0) }
        Button("Add note") { entries.append(.init()) }
            .disabled(entries.count >= 30)
    }
}
